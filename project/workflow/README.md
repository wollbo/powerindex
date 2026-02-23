# PowerIndex CRE Workflows

This folder contains the Chainlink Runtime Environment (CRE) workflows
used in PowerIndex.

There are two workflows:

1.  `publisher.ts` --- Production-style publisher (writes directly
    on-chain)
2.  `main.ts` --- Request-based workflow (used in local Anvil demo)

------------------------------------------------------------------------

## 1. Publisher Workflow (`publisher.ts`)

This workflow publishes the Nord Pool Day-ahead electricity index
directly to `DailyIndexConsumer`.

### What it does

-   Cron-triggered workflow
-   Uses OAuth2 to fetch Nord Pool Day-ahead prices
-   Computes D+1 delivery date (today + 1 day UTC)
-   Fetches all bidding zones in a single batched API request
-   Supports 92 / 96 / 100 periods (DST-safe)
-   Supports negative prices (int256-safe)
-   Computes deterministic dataset hash
-   Skips already committed dates
-   Writes report on-chain via `writeReport`

### Simulate

From this folder:

    cre workflow simulate workflow   -T publisher-settings   --trigger-index 0   --non-interactive   --env ./.env

### Broadcast to Sepolia

    cre workflow simulate workflow   -T publisher-settings   --trigger-index 0   --non-interactive   --env ./.env   --broadcast

------------------------------------------------------------------------

## 2. Request Workflow (`main.ts`) --- Local Demo

This workflow is used together with the local Anvil demo and
`RequestRegistry`.

Flow:

1.  Frontend creates a request on-chain
2.  Workflow reads request parameters
3.  Computes index (demo mode or real API)
4.  Emits JSON payload
5.  Local script relays result via `LocalCREForwarder`

### Run via Makefile (repo root)

Demo mode:

    make simulate-request REQUEST_ID=1

Real Nord Pool API:

    make request REQUEST_ID=1

This writes:

    project/out/latest.json

------------------------------------------------------------------------

## Relay On-Chain (Local Anvil)

From repo root:

    make fulfill REQUEST_ID=1
    make read

The fulfill script:

-   Calls `RequestRegistry.markFulfilled(...)`
-   Encodes `(indexId, yyyymmdd, areaId, value1e6, datasetHash)`
-   Forwards report via `LocalCREForwarder`
-   Calls `DailyIndexConsumer.onReport(...)`

------------------------------------------------------------------------

## Dataset Hash Construction

For each period:

    u32(periodIndex) ++ int256(value1e6)

Then:

    datasetHash = keccak256(concatenatedBytes)

This ensures:

-   Deterministic reproducibility
-   Verifiable linkage between dataset and committed value
-   Full support for negative prices

------------------------------------------------------------------------

## Configuration

Workflow configuration lives under:

-   `workflow.yaml` --- Target settings
-   `config.publisher.json`
-   `config.staging.json`

Common fields:

-   `schedule`
-   `tokenUrl`
-   `apiUrl`
-   `market`
-   `areas`
-   `currency`
-   `indexName`
-   `chainName`
-   `consumerAddress`
-   `gasLimit`
-   `publishHourUtc`
-   `dryRunOnchain`
-   `forceRun`

------------------------------------------------------------------------

## Secrets

Secrets are referenced by name (values not committed):

-   `NORDPOOL_BASIC_AUTH`
-   `NORDPOOL_USERNAME`
-   `NORDPOOL_PASSWORD`
-   `NORDPOOL_SCOPE`

Use `project/.env.example` and `secrets.example.yaml` as templates.

------------------------------------------------------------------------

## Output Payload (Request Workflow)

`project/out/latest.json` contains:

-   `indexName`
-   `area`
-   `date`
-   `dateNum`
-   `currency`
-   `value1e6`
-   `datasetHashHex`
-   `periodCount`

The publisher workflow does not emit JSON; it writes directly on-chain.
