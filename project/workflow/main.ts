import {
  CronCapability,
  HTTPClient,
  handler,
  Runner,
  consensusMedianAggregation,
  type Runtime,
  type HTTPSendRequester,
} from "@chainlink/cre-sdk";

type Config = {
  schedule: string;
  tokenUrl: string;
  apiUrl: string;
  market: "DayAhead";
  area: string;
  currency: "EUR" | "NOK" | "SEK" | "DKK" | "GBP" | "PLN" | "RON";
  date: string;

  // Local-only until CRE Vault access
  NORDPOOL_BASIC_AUTH: string;
  NORDPOOL_USERNAME: string;
  NORDPOOL_PASSWORD: string;
  NORDPOOL_SCOPE: string;

  demoMode?: boolean;
  demoDailyAvg?: number;
  indexName: string;
  valueDecimals: number;

};


type TokenResponse = {
  access_token: string;
  expires_in: number;
  token_type: "Bearer";
};

type NordPoolAreaPrices = {
  deliveryDateCET: string;
  updatedAt: string;
  status: "Missing" | "Preliminary" | "Final" | "Cancelled";
  unit: string;
  currency: string;
  exchangeRate: number;
  marketMainCurrency: string;
  averagePrice: number;
  minPrice: number;
  maxPrice: number;
  prices: Array<{
    deliveryStart: string;
    deliveryEnd: string;
    price: number | null;
  }>;
  market: "DayAhead";
  deliveryArea: string;
};

type NordPoolPricesByAreasResponse = NordPoolAreaPrices[];

function formUrlEncode(params: Record<string, string>) {
  return Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
}

// Minimal base64 encoder for Uint8Array (avoids Buffer)
function toBase64(bytes: Uint8Array): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let out = "";
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += alphabet[(n >> 18) & 63] + alphabet[(n >> 12) & 63] + alphabet[(n >> 6) & 63] + alphabet[n & 63];
  }
  if (i < bytes.length) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const n = (a << 16) | (b << 8);
    out += alphabet[(n >> 18) & 63] + alphabet[(n >> 12) & 63];
    out += i + 1 < bytes.length ? alphabet[(n >> 6) & 63] : "=";
    out += "=";
  }
  return out;
}

function computeDailyAverageFromPrices(prices: NordPoolAreaPrices["prices"]) {
  const vals = prices.map((p) => p.price).filter((x): x is number => typeof x === "number");
  const n = vals.length;

  // DST-safe: 23/24/25 periods
  if (n !== 92 && n !== 96 && n !== 100) {
    throw new Error(`Unexpected period count ${n} (expected 92/96/100).`);
  }

  let sum = 0;
  for (const v of vals) sum += v;
  return { average: sum / n, periodCount: n };
}

function yyyymmdd(date: string): number {
  // "2026-01-25" -> 20260125
  return Number(date.replaceAll("-", ""));
}

function scaleFixed(x: number, decimals: number): bigint {
  const factor = 10 ** decimals;
  return BigInt(Math.round(x * factor));
}

const onCronTrigger = (runtime: Runtime<Config>): string => {
  const http = new HTTPClient();

  function getSecret(runtime: Runtime<Config>, name: keyof Config): string {
    const v = runtime.config[name];
    if (typeof v === "string" && v.length > 0) return v;
    throw new Error(`Missing secret/config: ${String(name)}`);
  }

  // Secrets (TS API)
 /*
  const basicAuthB64 = runtime.getSecret({ id: "NORDPOOL_BASIC_AUTH" }).result().value;
  const username = runtime.getSecret({ id: "NORDPOOL_USERNAME" }).result().value;
  const password = runtime.getSecret({ id: "NORDPOOL_PASSWORD" }).result().value;
  const scope = runtime.getSecret({ id: "NORDPOOL_SCOPE" }).result().value;
*/
  const basicAuthB64 = getSecret(runtime, "NORDPOOL_BASIC_AUTH");
  const username = getSecret(runtime, "NORDPOOL_USERNAME");
  const password = getSecret(runtime, "NORDPOOL_PASSWORD");
  const scope = getSecret(runtime, "NORDPOOL_SCOPE");
  // Core node-level logic: POST token -> GET prices -> compute average (returns number)
  const fetchDailyAvg = (sendRequester: HTTPSendRequester): number => {
      if (runtime.config.demoMode) {
        const v = runtime.config.demoDailyAvg ?? 42.0;
        runtime.log(`DEMO MODE: returning stub dailyAvg=${v}`);
        return v;
      }

    const bodyStr = formUrlEncode({
      grant_type: "password",
      scope,
      username,
      password,
    });

    const tokenResp = sendRequester
      .sendRequest({
        url: runtime.config.tokenUrl,
        method: "POST",
        headers: {
          Authorization: `Basic ${basicAuthB64}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: toBase64(new TextEncoder().encode(bodyStr)),
      })
      .result();

    if (tokenResp.statusCode !== 200) {
      throw new Error(`Token request failed: ${tokenResp.statusCode}`);
    }

    const tokenJson = JSON.parse(new TextDecoder().decode(tokenResp.body)) as TokenResponse;
    if (!tokenJson.access_token) throw new Error("Token response missing access_token.");

    const { apiUrl, market, area, currency, date } = runtime.config;
    const url =
      `${apiUrl}?market=${encodeURIComponent(market)}` +
      `&areas=${encodeURIComponent(area)}` +
      `&currency=${encodeURIComponent(currency)}` +
      `&date=${encodeURIComponent(date)}`;

    const pricesResp = sendRequester
      .sendRequest({
        url,
        method: "GET",
        headers: { Authorization: `Bearer ${tokenJson.access_token}` },
      })
      .result();

    if (pricesResp.statusCode !== 200) {
      throw new Error(`Prices request failed: ${pricesResp.statusCode}`);
    }

    const data = JSON.parse(new TextDecoder().decode(pricesResp.body)) as NordPoolPricesByAreasResponse;
    if (!Array.isArray(data) || data.length === 0) throw new Error("Nord Pool response empty.");

    const item = data[0];
    if (item.status !== "Final") throw new Error(`Auction status not final: ${item.status}`);

    const { average, periodCount } = computeDailyAverageFromPrices(item.prices);

    const diff = Math.abs(item.averagePrice - average);
    if (diff > 0.01) runtime.log(`Warning: computed avg differs from api averagePrice by ${diff}`);

    runtime.log(`Computed avg=${average} from ${periodCount} periods`);
    return average;
  };

  // IMPORTANT: high-level sendRequest wraps runInNodeMode + consensus . :contentReference[oaicite:1]{index=1}
  const dailyAvg = http
    .sendRequest(runtime, fetchDailyAvg, consensusMedianAggregation<number>())()
    .result();

  const dateNum = yyyymmdd(runtime.config.date);
  const valueScaled = scaleFixed(dailyAvg, runtime.config.valueDecimals);

  const value1e6 = BigInt(Math.round(dailyAvg * 1_000_000));

  const preimage = `${runtime.config.indexName}|${runtime.config.area}|${dateNum}|${runtime.config.currency}|${value1e6.toString()}`;


  const payload = {
    indexName: runtime.config.indexName,
    area: runtime.config.area,
    date: runtime.config.date,
    dateNum,
    currency: runtime.config.currency,
    value1e6: value1e6.toString(),
    preimage,
};

  // Print a single-line JSON marker we can grep
  runtime.log(`POWERINDEX_JSON ${JSON.stringify(payload)}`);


  runtime.log(`INDEX_READY preimage=${preimage}`);

  runtime.log(
    `SOLIDITY_CALL commitDailyIndex(indexName="${runtime.config.indexName}", dateNum=${dateNum}, area="${runtime.config.area}", valueScaled=${valueScaled.toString()}, currency="${runtime.config.currency}")`
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
