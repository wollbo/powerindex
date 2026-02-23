import {
  CronCapability,
  HTTPClient,
  EVMClient,
  handler,
  Runner,
  type NodeRuntime,
  type Runtime,
  getNetwork,
  encodeCallMsg,
  bytesToHex,
  hexToBase64,
  LAST_FINALIZED_BLOCK_NUMBER,
} from "@chainlink/cre-sdk";

import { keccak_256 } from "@noble/hashes/sha3.js";
import { bytesToHex as nobleBytesToHex } from "@noble/hashes/utils.js";

import {
  encodeFunctionData,
  decodeFunctionResult,
  parseAbiParameters,
  encodeAbiParameters,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";

type Config = {
  schedule: string;

  tokenUrl: string;
  apiUrl: string;
  market: "DayAhead";
  currency: "EUR" | "NOK" | "SEK" | "DKK" | "GBP" | "PLN" | "RON";

  areas: string[];
  indexName: string;

  // onchain target
  chainName: string; // e.g. "ethereum-testnet-sepolia"
  consumerAddress: Address;
  gasLimit: string;

  // gating
  publishHourUtc: number;
  forceRun?: boolean;
  dryRunOnchain?: boolean;

  // secrets (resolved from config OR env)
  NORDPOOL_BASIC_AUTH?: string;
  NORDPOOL_USERNAME?: string;
  NORDPOOL_PASSWORD?: string;
  NORDPOOL_SCOPE?: string;
};

type TokenResponse = {
  access_token: string;
  expires_in: number;
  token_type: "Bearer";
};

type NordPoolAreaPrices = {
  market?: string;
  deliveryArea: string; // <- IMPORTANT (e.g. "SE2")
  status: "Missing" | "Preliminary" | "Final" | "Cancelled";
  averagePrice: number;
  prices: Array<{
    deliveryStart: string;
    deliveryEnd: string;
    price: number | null;
  }>;
};

type NordPoolPricesByAreasResponse = NordPoolAreaPrices[];


function formUrlEncode(params: Record<string, string>) {
  return Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
}

function yyyymmdd(date: string): number {
  return Number(date.replaceAll("-", ""));
}

function todayUtcYyyyMmDd(): string {
  const d = new Date();
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function addDaysUtc(yyyyMmDd: string, days: number): string {
  const [y, m, d] = yyyyMmDd.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  const yyyy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(dt.getUTCDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}


function nowUtcHour(): number {
  return new Date().getUTCHours();
}

// uint32 -> 4 bytes BE
function u32be(n: number): Uint8Array {
  const b = new Uint8Array(4);
  b[0] = (n >>> 24) & 0xff;
  b[1] = (n >>> 16) & 0xff;
  b[2] = (n >>> 8) & 0xff;
  b[3] = n & 0xff;
  return b;
}

// int256 -> 32 bytes two's complement BE
function i256be(x: bigint): Uint8Array {
  const b = new Uint8Array(32);
  let v = x;

  if (v < 0n) v = (1n << 256n) + v;

  for (let i = 31; i >= 0; i--) {
    b[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return b;
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const len = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(len);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

function keccakHex(bytes: Uint8Array): `0x${string}` {
  return (`0x${nobleBytesToHex(keccak_256(bytes))}`) as `0x${string}`;
}

function computeDailyFromPrices(prices: NordPoolAreaPrices["prices"]) {
  const vals = prices
    .filter((p) => typeof p.price === "number")
    .map((p) => ({ start: p.deliveryStart, price: p.price as number }))
    .sort((a, b) => a.start.localeCompare(b.start));

  const n = vals.length;
  if (n !== 92 && n !== 96 && n !== 100) {
    throw new Error(`Unexpected period count ${n} (expected 92/96/100).`);
  }

  const points = vals.map((v, i) => ({
    periodIndex: i,
    value1e6: BigInt(Math.round(v.price * 1e6)),
  }));

  let sum = 0n;
  for (const p of points) sum += p.value1e6;
  const avg1e6 = sum / BigInt(points.length);

  const packedParts: Uint8Array[] = [];
  for (const p of points) {
    packedParts.push(u32be(p.periodIndex));
    packedParts.push(i256be(p.value1e6));
  }
  const datasetHash = keccakHex(concatBytes(packedParts));

  return { avg1e6, periodCount: n, datasetHash };
}

function base64EncodeUtf8(s: string): string {
  return Buffer.from(s, "utf8").toString("base64");
}

const DailyIndexConsumerAbi = [
  {
    type: "function",
    name: "commitments",
    stateMutability: "view",
    inputs: [
      { name: "indexId", type: "bytes32" },
      { name: "areaId", type: "bytes32" },
      { name: "yyyymmdd", type: "uint32" },
    ],
    outputs: [
      { name: "datasetHash", type: "bytes32" },
      { name: "value1e6", type: "int256" },
      { name: "reporter", type: "address" },
      { name: "reportedAt", type: "uint64" },
    ],
  },
] as const;

function areaId(area: string): Hex {
  // keccak256(bytes(area)) -> 0x...
  // viem doesn't ship keccak by default, so use noble sha3 impl:
  return keccakHex(new TextEncoder().encode(area));
}

function indexId(indexName: string): Hex {
  return keccakHex(new TextEncoder().encode(indexName));
}

const onCronTrigger = (runtime: Runtime<Config>): string => {
  const http = new HTTPClient();
  const nodeRuntime = runtime as unknown as NodeRuntime<Config>;

  const getSecret = (id: string): string => {
    const s = runtime.getSecret({ id }).result();
    if (!s?.value || s.value.length === 0) throw new Error(`Missing secret: ${id}`);
    return s.value;
  };

  // Gate to after publish hour UTC
  const publishHour = runtime.config.publishHourUtc ?? 12;

  if (!runtime.config.forceRun && nowUtcHour() < publishHour) {
    runtime.log(`Publisher gate: now < ${publishHour}:00 UTC, skipping`);
    return "skipped";
  }
  if (runtime.config.forceRun) {
    runtime.log("Publisher gate: forceRun=true (time gate bypassed)");
  }
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: runtime.config.chainName,
    isTestnet: true,
  });
  if (!network) throw new Error(`Network not found: ${runtime.config.chainName}`);

  const evmClient = new EVMClient(network.chainSelector.selector);

  const date = addDaysUtc(todayUtcYyyyMmDd(), 1); // DayAhead delivery date
  const dateNum = yyyymmdd(date);
  const idxId = indexId(runtime.config.indexName);

  const basicAuthB64 = getSecret("NORDPOOL_BASIC_AUTH");
  const username = getSecret("NORDPOOL_USERNAME");
  const password = getSecret("NORDPOOL_PASSWORD");
  const scope = getSecret("NORDPOOL_SCOPE");

  const decodeBody = (b: Uint8Array) => new TextDecoder().decode(b);

  let committed = 0;
  let skippedAlready = 0;
  let skippedNotFinal = 0;
  let errors = 0;

    // ---------------------------
  // HTTP: 1 token + 1 batched prices call (ALL areas)
  // ---------------------------

  const areasParam = runtime.config.areas.join(",");

  // 1) OAuth2 Token (once)
  const bodyStr = formUrlEncode({
    grant_type: "password",
    scope,
    username,
    password,
  });

  const tokenResp = http
    .sendRequest(nodeRuntime, {
      url: runtime.config.tokenUrl,
      method: "POST",
      headers: {
        Authorization: `Basic ${basicAuthB64}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: base64EncodeUtf8(bodyStr),
    })
    .result();

  if (tokenResp.statusCode !== 200) {
    throw new Error(`Token request failed: ${tokenResp.statusCode}`);
  }

  const tokenJson = JSON.parse(decodeBody(tokenResp.body)) as TokenResponse;
  if (!tokenJson.access_token) throw new Error("Token response missing access_token.");

  // 2) Prices (once) for ALL areas
  const pricesUrl =
    `${runtime.config.apiUrl}?market=${encodeURIComponent(runtime.config.market)}` +
    `&areas=${encodeURIComponent(areasParam)}` +
    `&currency=${encodeURIComponent(runtime.config.currency)}` +
    `&date=${encodeURIComponent(date)}`;

  const pricesResp = http
    .sendRequest(nodeRuntime, {
      url: pricesUrl,
      method: "GET",
      headers: { Authorization: `Bearer ${tokenJson.access_token}` },
    })
    .result();

  if (pricesResp.statusCode !== 200) {
    throw new Error(`Prices request failed: ${pricesResp.statusCode}`);
  }

  const allAreasData = JSON.parse(decodeBody(pricesResp.body)) as NordPoolPricesByAreasResponse;
  if (!Array.isArray(allAreasData) || allAreasData.length === 0) {
    throw new Error("Nord Pool response empty.");
  }

  // Map deliveryArea -> payload
  const byDeliveryArea = new Map<string, NordPoolAreaPrices>();
  for (const item of allAreasData) {
    if (item?.deliveryArea) byDeliveryArea.set(item.deliveryArea, item);
  }

  for (const area of runtime.config.areas) {
    try {
      const aId = areaId(area);

      // Read commitment first to skip already published
      if (!runtime.config.dryRunOnchain) {
        const callData = encodeFunctionData({
          abi: DailyIndexConsumerAbi,
          functionName: "commitments",
          args: [idxId, aId, dateNum],
        });

        const call = evmClient
          .callContract(runtime, {
            call: encodeCallMsg({
              from: zeroAddress,
              to: runtime.config.consumerAddress,
              data: callData,
            }),
            blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
          })
          .result();

        // Some environments may return empty data if the contract isn't deployed / wrong address.
        const hexData = bytesToHex(call.data);
        if (hexData !== "0x") {
          const decoded = decodeFunctionResult({
            abi: DailyIndexConsumerAbi,
            functionName: "commitments",
            data: hexData,
          }) as readonly [Hex, bigint, Address, bigint];

          const reportedAt = decoded[3];
          if (reportedAt !== 0n) {
            skippedAlready++;
            continue;
          }
        }
      } else {
        runtime.log(`DRY_RUN mode: skipping onchain commitments check for area=${area}`);
      }
      
      const item = byDeliveryArea.get(area);
      if (!item) {
        errors++;
        runtime.log(`ERROR area=${area}: missing from Nord Pool response (deliveryArea not found)`);
        continue;
      }

      if (item.status !== "Final") {
        skippedNotFinal++;
        runtime.log(`Area ${area}: status=${item.status}, skipping`);
        continue;
      }

      const { avg1e6, periodCount, datasetHash } = computeDailyFromPrices(item.prices);

      if (runtime.config.dryRunOnchain) {
        runtime.log(
            `DRY_RUN area=${area} date=${date} value1e6=${avg1e6.toString()} periodCount=${periodCount} datasetHash=${datasetHash}`
        );
        committed++;
        continue;
      }

      // Encode consumer report ABI (matches onReport decode)
      const reportPayload = encodeAbiParameters(
        parseAbiParameters("bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, int256 value1e6, bytes32 datasetHash"),
        [idxId, dateNum, aId, avg1e6, datasetHash]
      );

      // signed report
      const reportResponse = runtime
        .report({
          encodedPayload: hexToBase64(reportPayload),
          encoderName: "evm",
          signingAlgo: "ecdsa",
          hashingAlgo: "keccak256",
        })
        .result();

      // submit report onchain
      const writeRes = evmClient
        .writeReport(runtime, {
          receiver: runtime.config.consumerAddress,
          report: reportResponse,
          gasConfig: { gasLimit: runtime.config.gasLimit },
        })
        .result();

      const txHash = bytesToHex(writeRes.txHash || new Uint8Array(32));
      committed++;

      runtime.log(
        `PUBLISHED area=${area} date=${date} value1e6=${avg1e6.toString()} periodCount=${periodCount} datasetHash=${datasetHash} tx=${txHash}`
      );
      runtime.log(`Etherscan: https://sepolia.etherscan.io/tx/${txHash}`);
    } catch (e) {
      errors++;
      runtime.log(`ERROR area=${area}: ${(e as Error).message}`);
    }
  }

  runtime.log(
    `Publisher summary | date (delivery)=${date} committed=${committed} skippedAlready=${skippedAlready} skippedNotFinal=${skippedNotFinal} errors=${errors}`
  );

  return "ok";
};

const initWorkflow = (config: Config) => {
  const cron = new CronCapability();
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}