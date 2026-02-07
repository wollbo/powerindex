# PowerIndex (Chainlink Convergence Hackathon)

PowerIndex publishes a daily electricity price index (Nord Pool Day-ahead average) using a Chainlink Runtime Environment (CRE) workflow. The workflow computes an index off-chain, reaches consensus, and posts an ABI-encoded report on-chain to a consumer contract.
## Architecture

CRE Workflow (TypeScript)
→ (ABI-encoded report payload)
→ DailyIndexConsumer.onReport()
→ events + storage

## Repo layout

- `src/`, `script/`, `test/` — Solidity consumer + Foundry scripts/tests
- `project/` — CRE project (workflow code + configs)
- `powerapp/` — Frontend explorer (Vite + wagmi + RainbowKit) *(if included in this repo)*

## Prerequisites

- Foundry: `forge`, `cast`, `anvil`
- Node.js + npm (for frontend)
- CRE CLI (for workflow simulation / deployment)

## Quickstart (Local / Anvil)

Terminal A (start Anvil):
- `make anvil`

Terminal B (deploy + seed):
- `make build`
- `make test`
- `make deploy`
- `make seed`
- `make read`

### Optional: Simulate CRE and relay on-chain

In `project/` (CRE simulation):
- `cd project`
- `cre workflow simulate workflow -T staging-settings --trigger-index 0 --non-interactive`

Back at repo root (relay latest payload to the consumer):
- `cd ..`
- `make relay`
- `make read`

## Configuration

This repo uses two environment contexts:

- **Foundry (repo root)**: `.env` (see `.env.example`)
- **CRE project (`project/`)**: `project/.env` (see `project/.env.example`)

Do not commit secrets. `.env` and `secrets.yaml` are ignored by git.

## Report format (ABI)

The consumer currently expects this report encoding:

`(bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, uint256 value1e6, bytes32 dataHash)`

## Notes

- Local testing uses Anvil. Import Anvil account #0 into MetaMask if you want to use the admin-gated UI.
- Nord Pool API access is required to run the real data fetch path (workflow currently supports stub/demo mode).
