# PowerIndex (Chainlink Convergence Hackathon)

PowerIndex publishes a daily electricity price index (Nord Pool Day-ahead average) using a Chainlink Runtime Environment (CRE) workflow. The workflow computes an index off-chain, reaches consensus, and posts an ABI-encoded report on-chain to a consumer contract.
## Architecture

CRE Workflow (TypeScript)
→ (ABI-encoded report payload)
→ DailyIndexConsumer.onReport()
→ events + storage

The workflow:
- Fetches Nord Pool day-ahead prices
- Computes daily average (supports 92/96/100 periods for DST handling)
- Canonically packs (periodIndex, value1e6) pairs
- Computes datasetHash = keccak256(packedPeriods)
- Submits (value1e6, datasetHash) on-chain

## Repo layout

- `src/`, `script/`, `test/` — Solidity consumer + Foundry scripts/tests
- Bun (for workflow TypeScript runtime)
- `project/` — CRE project (workflow code + configs)

## Prerequisites

- Foundry: `forge`, `cast`, `anvil`
- CRE CLI (for workflow simulation / deployment)

## Quickstart (Local / Anvil)

Terminal A (start Anvil):
- `make anvil`

Terminal B (deploy + simulate CRE):
- `make build`
- `make test`
- `make deploy`
- `make allow-sender`

This:

- Deploys DailyIndexConsumer
- Deploys LocalCREForwarder
- Authorizes your local EOA as allowed forwarder sender

### Simulate CRE and relay on-chain

- `make simulate`
- `make relay`
- `make read`

Flow:

- `make simulate`
    - Runs CRE workflow locally
    - Writes `project/out/latest.json`
- `make relay`
    - Reads `latest.json`
    - ABI-encodes report
    - Forwards via `LocalCREForwarder`
- `make read`
    - Reads commitment from on-chain storage
    
## Configuration

This repo uses two environment contexts:

- **Foundry (repo root)**: `.env` (see `.env.example`)
- **CRE project (`project/`)**: `project/.env` (see `project/.env.example`)

Do not commit secrets. `.env` and `secrets.yaml` are ignored by git.

## Report format (ABI)

The consumer currently expects this report encoding:

`(bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, int256 value1e6, bytes32 dataHash, uint32 periodCount)`

where:
- `value1e6` Signed daily average price scaled by 1e6 (supports negative prices)
- `dataHash` keccak256 of canonical packed bytes:
    ```
        keccak256(
        u32(periodIndex) ++
        int256(value1e6)
        for each period in ascending order
    ) 
    ```
- `periodCount` Number of periods used (typically 92, 96, or 100)

This ensures:

- The committed value matches the exact dataset used
- The hash can be independently recomputed off-chain
- Negative prices are fully supported

## Notes

- Local testing uses Anvil. Import Anvil account #0 into MetaMask if you want to use the admin-gated UI.
- Nord Pool Market data API access is required to run the real data fetch path (workflow currently supports demo mode for local development).
