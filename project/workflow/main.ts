import {
  CronCapability,
  HTTPClient,
  handler,
  Runner,
  NodeRuntime,
  type Runtime,
} from "@chainlink/cre-sdk";

import { keccak_256 } from "@noble/hashes/sha3.js";
import { bytesToHex } from "@noble/hashes/utils.js";


type Config = {
  schedule: string;
  tokenUrl: string;
  apiUrl: string;
  market: "DayAhead";
  area: string;
  currency: "EUR" | "NOK" | "SEK" | "DKK" | "GBP" | "PLN" | "RON";
  date: string;

  // local demo until vault
  NORDPOOL_BASIC_AUTH: string;
  NORDPOOL_USERNAME: string;
  NORDPOOL_PASSWORD: string;
  NORDPOOL_SCOPE: string;

  demoMode?: boolean;
  demoDailyAvg?: number;

  indexName: string;
};

type TokenResponse = {
  access_token: string;
  expires_in: number;
  token_type: "Bearer";
};

type NordPoolAreaPrices = {
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

  if (v < 0n) {
    // two's complement in 256 bits: x mod 2^256
    v = (1n << 256n) + v;
  }
  // now v is [0, 2^256)
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
  return (`0x${bytesToHex(keccak_256(bytes))}`) as `0x${string}`;
}
function computeDailyFromPrices(prices: NordPoolAreaPrices["prices"]) {
  const vals = prices
    .filter((p) => typeof p.price === "number")
    .map((p) => ({ start: p.deliveryStart, price: p.price as number }))
    .sort((a, b) => a.start.localeCompare(b.start));

  const n = vals.length;
  // 15m: normally 96; DST can produce 92/100
  if (n !== 92 && n !== 96 && n !== 100) {
    throw new Error(`Unexpected period count ${n} (expected 92/96/100).`);
  }

  const points = vals.map((v, i) => {
    const value1e6 = BigInt(Math.round(v.price * 1e6));
    return { periodIndex: i, value1e6 };
  });

  let sum = 0n;
  for (const p of points) sum += p.value1e6;
  const avg1e6 = sum / BigInt(points.length);

  // hash all datapoints: keccak( (u32 idx || i256 value1e6) * N )
  const packedParts: Uint8Array[] = [];
  for (const p of points) {
    packedParts.push(u32be(p.periodIndex));
    packedParts.push(i256be(p.value1e6));
  }
  const datasetHash = keccakHex(concatBytes(packedParts));

  return { avg1e6, periodCount: n, datasetHash };
}


const onCronTrigger = (runtime: Runtime<Config>): string => {
  const http = new HTTPClient();
  const nodeRuntime = runtime as unknown as NodeRuntime<Config>;

  const getCfg = (k: keyof Config) => {
    const v = runtime.config[k];
    if (typeof v === "string" && v.length > 0) return v;
    throw new Error(`Missing config: ${String(k)}`);
  };
  const decodeBody = (b: Uint8Array) => new TextDecoder().decode(b);


 // demo mode
if (runtime.config.demoMode) {
  const dateNum = yyyymmdd(runtime.config.date);
  const value1e6 = BigInt(Math.round((runtime.config.demoDailyAvg ?? 42.42) * 1e6));

  // keccakHex returns 0x...
  const datasetHash0x = keccakHex(new TextEncoder().encode("DEMO_DATASET"));

  const payload = {
    indexName: runtime.config.indexName,
    area: runtime.config.area,
    date: runtime.config.date,
    dateNum,
    currency: runtime.config.currency,
    value1e6: value1e6.toString(),
    datasetHashHex: datasetHash0x.slice(2),
    periodCount: 96,
  };

  runtime.log(`POWERINDEX_JSON ${JSON.stringify(payload)}`);
  return "ok";
}


  const basicAuthB64 = getCfg("NORDPOOL_BASIC_AUTH");
  const username = getCfg("NORDPOOL_USERNAME");
  const password = getCfg("NORDPOOL_PASSWORD");
  const scope = getCfg("NORDPOOL_SCOPE");

  // 1) Token
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
      body: bodyStr,
    })
    .result();

  if (tokenResp.statusCode !== 200) {
    throw new Error(`Token request failed: ${tokenResp.statusCode}`);
  }

  const tokenJson = JSON.parse(decodeBody(tokenResp.body)) as TokenResponse;
; // body is string in this SDK
  if (!tokenJson.access_token) throw new Error("Token response missing access_token.");

  // 2) Prices
  const { apiUrl, market, area, currency, date } = runtime.config;
  const url =
    `${apiUrl}?market=${encodeURIComponent(market)}` +
    `&areas=${encodeURIComponent(area)}` +
    `&currency=${encodeURIComponent(currency)}` +
    `&date=${encodeURIComponent(date)}`;

  const pricesResp = http
    .sendRequest(nodeRuntime, {
      url,
      method: "GET",
      headers: { Authorization: `Bearer ${tokenJson.access_token}` },
    })
    .result();

  if (pricesResp.statusCode !== 200) {
    throw new Error(`Prices request failed: ${pricesResp.statusCode}`);
  }

  const data = JSON.parse(decodeBody(pricesResp.body)) as NordPoolPricesByAreasResponse;
  if (!Array.isArray(data) || data.length === 0) throw new Error("Nord Pool response empty.");

  const item = data[0];
  if (item.status !== "Final") throw new Error(`Auction status not final: ${item.status}`);

  const { avg1e6, periodCount, datasetHash } = computeDailyFromPrices(item.prices);

  const dateNum = yyyymmdd(runtime.config.date);

  const payload = {
    indexName: runtime.config.indexName,
    area: runtime.config.area,
    date: runtime.config.date,
    dateNum,
    currency: runtime.config.currency,
    avg1e6: avg1e6.toString(),      
    datasetHash,                    
    periodCount,
  };

  runtime.log(`POWERINDEX_JSON ${JSON.stringify(payload)}`);
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
