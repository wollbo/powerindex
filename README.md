# PowerIndex

PowerIndex is a verifiable electricity price benchmark for Nordic power markets built using the **Chainlink Runtime Environment (CRE)**.

A CRE workflow fetches Nord Pool Day-Ahead electricity market data, computes a deterministic daily price index, and publishes a signed commitment on-chain. Financial contracts can then settle against this benchmark.

The workflow commits not only the final index value, but also a **dataset hash** that acts as a cryptographic fingerprint of the underlying market data used in the calculation. This allows the benchmark to be independently reproduced and verified from the public Nord Pool dataset.

To demonstrate the use case, the project includes a **binary options marketplace** where contracts settle against the published index value.

## Architecture

CRE Workflow (TypeScript)  
→ Fetch Nord Pool market data  
→ Compute deterministic index + datasetHash  
→ ABI-encode report  
→ Submit to DailyIndexConsumer contract  

The workflow:

- Fetches Nord Pool Day-ahead prices (D+1 delivery date)
- Supports all bidding zones (NO1–NO5, DK1–DK2, FI, SE1–SE4)
- Computes deterministic daily VWAP
- Canonically packs `(periodIndex, value1e6)` pairs
- Computes `datasetHash = keccak256(packedPeriods)`
- Submits `(indexId, yyyymmdd, areaId, value1e6, datasetHash)` on-chain

## Repo layout

-   `src/`, `script/`, `test/` --- Solidity contracts + Foundry
    scripts/tests\
-   `project/` --- CRE workflows (publisher + request workflow)\
-   `deployments/` --- Local deployment outputs (Anvil)

## Prerequisites

-   Foundry: `forge`, `cast`, `anvil`
-   CRE CLI
-   Node/Bun (for workflow runtime)


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

## Project Origin

This project builds on an earlier prototype ("Northpole") created during the Chainlink Spring 2022 Hackathon.

The original version demonstrated the idea of settling financial contracts against a Nordic electricity price index, but relied on a custom external adapter, unofficial APIs, and bridge infrastructure hosted on AWS.

PowerIndex revisits that idea using the **Chainlink Runtime Environment (CRE)** to implement the data pipeline as a verifiable workflow. CRE removes the need for custom bridges and external infrastructure, allowing the benchmark computation and reporting logic to be expressed directly within the Chainlink ecosystem.
