# PowerIndex (Chainlink Convergence Hackathon)

PowerIndex publishes a daily electricity price index (Nord Pool
Day-ahead average) using a Chainlink Runtime Environment (CRE)
workflow.\
The workflow computes an index off-chain from real Nord Pool market
data, produces a deterministic dataset hash, and publishes an
ABI-encoded report on-chain to a consumer contract.

## Architecture

CRE Workflow (TypeScript)\
→ (ABI-encoded report payload)\
→ DailyIndexConsumer.onReport()\
→ events + storage

The workflow:

-   Fetches Nord Pool Day-ahead prices (D+1 delivery date)
-   Supports all bidding zones (NO1--NO5, DK1--DK2, FI, SE1--SE4)
-   Computes daily average (supports 92 / 96 / 100 periods for DST
    handling)
-   Canonically packs (periodIndex, value1e6) pairs
-   Computes datasetHash = keccak256(packedPeriods)
-   Submits (indexId, yyyymmdd, areaId, value1e6, datasetHash) on-chain

## Repo layout

-   `src/`, `script/`, `test/` --- Solidity contracts + Foundry
    scripts/tests\
-   `project/` --- CRE workflows (publisher + request workflow)\
-   `deployments/` --- Local deployment outputs (Anvil)

## Prerequisites

-   Foundry: `forge`, `cast`, `anvil`
-   CRE CLI
-   Node/Bun (for workflow runtime)

## Quickstart (Local / Anvil)

Terminal A (start Anvil):

-   `make anvil`

Terminal B (deploy contracts):

-   `make build`
-   `make test`
-   `make deploy`
-   `make allow-sender`

This:

-   Deploys DailyIndexConsumer
-   Deploys LocalCREForwarder
-   Deploys RequestRegistry
-   Deploys NorthpoleOptionFactory
-   Authorizes your local EOA as allowed forwarder sender

## Local Request → Fulfillment Flow

1.  Create request (frontend or CLI)
2.  Run workflow locally
3.  Fulfill on-chain
4.  Read commitment

### Run workflow (demo mode)

-   `make simulate-request REQUEST_ID=1`

### Run workflow (real Nord Pool API)

-   `make request REQUEST_ID=1`

This writes:

-   `project/out/latest.json`

### Fulfill on-chain

-   `make fulfill REQUEST_ID=1`

This:

-   Calls `RequestRegistry.markFulfilled(...)`
-   Forwards encoded report via `LocalCREForwarder`
-   Calls `DailyIndexConsumer.onReport(...)`

### Read commitment

-   `make read`

Or:

    cast call <CONSUMER>   "commitments(bytes32,bytes32,uint32)(bytes32,int256,address,uint64)"   <indexId> <areaId> <yyyymmdd>   --rpc-url http://127.0.0.1:8545

## Sepolia Publisher (Real Data)

Publisher workflow:

-   `project/workflow/publisher.ts`

Features:

-   D+1 delivery logic (today + 1 day UTC)
-   Batched API request for all areas (rate-limit safe)
-   Skips already committed dates
-   Cron trigger (15 minutes)
-   Writes directly to DailyIndexConsumer

### Simulate

    cd project
    cre workflow simulate workflow   -T publisher-settings   --trigger-index 0   --non-interactive   --env ./.env

### Broadcast to Sepolia

    cre workflow simulate workflow   -T publisher-settings   --trigger-index 0   --non-interactive   --env ./.env   --broadcast

## Report format (ABI)

The consumer expects:

    (bytes32 indexId,
     uint32 yyyymmdd,
     bytes32 areaId,
     int256 value1e6,
     bytes32 datasetHash)

Where:

-   `value1e6` is the signed daily average scaled by 1e6
-   `datasetHash` is keccak256 of canonical packed period data:
    -   u32(periodIndex) ++ int256(value1e6) for each period in
        ascending order

This ensures:

-   Deterministic reproducibility
-   Verifiable linkage between dataset and committed value
-   Full support for negative prices

## Configuration

Two environment contexts:

-   Root `.env` --- Foundry (RPC, PK)
-   `project/.env` --- CRE + Nord Pool credentials

Do not commit secrets. `.env` and `secrets.yaml` are ignored by git.
