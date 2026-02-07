# PowerIndex CRE project

This folder contains the Chainlink Runtime Environment (CRE) workflow for computing a daily power index and producing an ABI-encoded report suitable for on-chain submission.

## What it does

- Cron-triggered workflow
- Fetches Nord Pool day-ahead prices (OAuth2 token flow)
- Computes daily average (supports 23/24/25 hour days; also compatible with 96×15m days)
- Uses BFT median aggregation over nodes for the numeric result
- Builds a canonical preimage + `dataHash`
- Emits/writes a JSON payload for local relaying (in simulation mode)

## Simulate locally

From the repo root:

- `cd project`
- `cre workflow simulate workflow -T staging-settings --trigger-index 0 --non-interactive`

Expected output includes logs like `INDEX_READY ...` and writes a payload JSON (commonly `out/latest.json`).

If your tooling uses a different output path, update the Makefile variable:
- `PAYLOAD_PATH=project/out/latest.json make relay`

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
- `preimage` (string)
