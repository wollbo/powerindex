PowerIndex CRE Workflow

This folder contains the Chainlink Runtime Environment (CRE) workflow for computing a daily Nord Pool power index and producing a JSON payload suitable for on-chain submission.

## What it does

-Cron-triggered workflow
-Fetches Nord Pool day-ahead prices (OAuth2 token flow)
-Computes daily average (supports 92/96/100 periods for DST)
-Supports negative prices (int256-safe)
-Builds a canonical dataset hash over all intraday periods
-Emits a JSON payload for local relaying
The dataset hash commits to all (periodIndex, int256 value1e6) pairs for the day.

## Simulate locally

From this folder:

`./run_workflow_a`

This will:

- Run cre workflow simulate
- Extract the POWERINDEX_JSON log line
- Write out/latest.json

## Relay On-Chain 

From the repo root:

- `make relay`
- `make read`

Ensure that `PAYLOAD_PATH=project/out/latest.json`

The relay script parses:

- indexName
- area
- dateNum
- value1e6
- datasetHashHex

and forwards the encoded report via LocalCREForwarder.


## Configuration

Workflow config lives under:

- `workflow/workflow.yaml` (target settings)
- plus any `config.*` files referenced by the target

Common fields include:
- `schedule`
- `tokenUrl`
- `apiUrl`
- `market`
- `area`
- `currency`
- `date` (for testing; later computed dynamically)
- `indexName`
- `valueDecimals`
- `demoMode`

## Secrets

This project expects secrets (names only, values not committed):
- `NORDPOOL_BASIC_AUTH`
- `NORDPOOL_USERNAME`
- `NORDPOOL_PASSWORD`
- `NORDPOOL_SCOPE`

Use `project/.env.example` as a template.

## Output payload schema (simulation)

A typical `out/latest.json` contains:

- `indexName` (string)
- `area` (string)
- `date` (string `YYYY-MM-DD`)
- `dateNum` (number `yyyymmdd`)
- `currency` (string)
- `value1e6` (string or number)
- `datasetHashHex` (string)
- `periodCount` (number)

This workflow produces a deterministic dataset hash suitable for verifiable on-chain settlement via DailyIndexConsumer.