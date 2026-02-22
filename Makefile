# Load .env if present (for local dev). Do not commit .env.
ifneq (,$(wildcard .env))
  include .env
  export $(shell sed 's/=.*//' .env)
endif

# ====== Config (override like: make deploy RPC_URL=... ) ======
RPC_URL ?= http://127.0.0.1:8545

# CRE project location (relative to repo root)
CRE_DIR ?= project

# Deployed consumer address persistence
CONSUMER_FILE := deployments/consumer.txt
CONSUMER := $(shell test -f $(CONSUMER_FILE) && cat $(CONSUMER_FILE))

# Same for forwarder
FORWARDER_FILE := deployments/forwarder.txt
FORWARDER := $(shell test -f $(FORWARDER_FILE) && cat $(FORWARDER_FILE))

# And for registry
REGISTRY_FILE := deployments/registry.txt
REGISTRY := $(shell test -f $(REGISTRY_FILE) && cat $(REGISTRY_FILE))

# And market
FACTORY_FILE := deployments/factory.txt
FACTORY := $(shell test -f $(FACTORY_FILE) && cat $(FACTORY_FILE))


# Latest CRE simulation output (or your own file)
PAYLOAD_PATH ?= $(CRE_DIR)/out/latest.json

# Default report params (used by `make report` and `make read`)
INDEX_NAME ?= NORDPOOL_DAYAHEAD_AVG_V1
AREA ?= NO1
DATE_NUM ?= 20260125
VALUE_1E6 ?= 42420000

PREMIUM_ETH ?= 0.1
PAYOUT_ETH ?= 1.0
STRIKE_1E6 ?= 40000000
DIR ?= 0
BUY_DEADLINE ?= 1771758000

# Default Currency
CURRENCY ?= EUR

# Default SEED parameters
SEED_DAYS ?= 7
SEED_AREAS ?= SE1 SE2 SE3 SE4 FI

# ====== Targets ======
.PHONY: help print anvil build test clean \
        ensure-pk ensure-consumer ensure-forwarder ensure-registry \
        deploy allow-sender request fulfill \
        manual-commit relay-json report relay read seed _seed_one demo \
        simulate simulate-request


# Backwards-compatible aliases
report: manual-commit
relay: relay-json


help:
	@echo "Targets:"
	@echo "  make anvil     - start local anvil node"
	@echo "  make build     - forge build"
	@echo "  make test      - forge test -v"
	@echo "  make deploy    - deploy DailyIndexConsumer and persist address"
	@echo "  make report    - send parameterized demo report (INDEX_NAME/AREA/DATE_NUM/VALUE_1E6)"
	@echo "  make relay     - relay JSON payload (PAYLOAD_PATH) to consumer.onReport()"
	@echo "  make read      - read commitment back for (INDEX_NAME/AREA/DATE_NUM)"
	@echo "  make seed      - send a small batch of demo reports"
	@echo "  make demo      - deploy + seed + read (quick sanity)"
	@echo "  make print     - print resolved variables"
	@echo "  make clean     - forge clean"
	@echo ""
	@echo "Vars:"
	@echo "  RPC_URL=$(RPC_URL)"
	@echo "  PK=<private key>"
	@echo "  CRE_DIR=$(CRE_DIR)"
	@echo "  PAYLOAD_PATH=$(PAYLOAD_PATH)"
	@echo "  CONSUMER=$(CONSUMER)"
	@echo "  INDEX_NAME=$(INDEX_NAME) AREA=$(AREA) DATE_NUM=$(DATE_NUM) VALUE_1E6=$(VALUE_1E6)"

print:
	@echo "RPC_URL=$(RPC_URL)"
	@echo "CRE_DIR=$(CRE_DIR)"
	@echo "PAYLOAD_PATH=$(PAYLOAD_PATH)"
	@echo "CONSUMER=$(CONSUMER)"
	@echo "INDEX_NAME=$(INDEX_NAME)"
	@echo "AREA=$(AREA)"
	@echo "DATE_NUM=$(DATE_NUM)"
	@echo "VALUE_1E6=$(VALUE_1E6)"
	@echo "FACTORY=$(FACTORY)"


anvil:
	anvil

build:
	forge build

test:
	forge test -v

ensure-pk:
	@if [ -z "$(PK)" ]; then \
		echo "Missing PK. Put PK=... in .env (recommended) or pass PK=... on the command line."; \
		exit 1; \
	fi

# Deploy consumer and forwarder and persist address (script should write deployments/.txt)
deploy: ensure-pk
	forge script script/DeployConsumer.s.sol:DeployConsumer \
	  --rpc-url $(RPC_URL) \
	  --private-key $(PK) \
	  --broadcast


ensure-consumer:
	@if [ -z "$(CONSUMER)" ]; then \
		echo "Consumer not deployed yet. Run: make deploy"; \
		exit 1; \
	fi


ensure-forwarder:
	@if [ -z "$(FORWARDER)" ]; then \
		echo "Forwarder not deployed yet. Run: make deploy"; \
		exit 1; \
	fi


allow-sender: ensure-forwarder ensure-pk
	ADDR=$$(cast wallet address --private-key $(PK)); \
	echo "Allowing sender $$ADDR on forwarder $(FORWARDER)"; \
	cast send $(FORWARDER) "setAllowedSender(address,bool)" $$ADDR true \
	  --rpc-url $(RPC_URL) --private-key $(PK) 


ensure-registry:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Registry not deployed yet. Run: make deploy"; \
		exit 1; \
	fi


ensure-factory:
	@if [ -z "$(FACTORY)" ]; then \
		echo "Factory not deployed yet. Run: make deploy"; \
		exit 1; \
	fi


request:
	@test -n "$(REQUEST_ID)" || (echo "Missing REQUEST_ID=..."; exit 1)
	@cd project && ./run_request_and_capture.sh "$(REQUEST_ID)" "$(REGISTRY)" "$(RPC_URL)" out real


fulfill: ensure-consumer ensure-forwarder ensure-registry
	@if [ -z "$(REQUEST_ID)" ]; then \
		echo "Missing REQUEST_ID. Example: make fulfill REQUEST_ID=0"; \
		exit 1; \
	fi
	PAYLOAD_PATH=$(PAYLOAD_PATH) CONSUMER=$(CONSUMER) FORWARDER=$(FORWARDER) REGISTRY=$(REGISTRY) REQUEST_ID=$(REQUEST_ID) \
	forge script script/FulfillRequestFromJson.s.sol:FulfillRequestFromJson \
	  --rpc-url $(RPC_URL) --private-key $(PK) --broadcast


manual-commit: ensure-consumer ensure-forwarder ensure-pk
	INDEX_NAME=$(INDEX_NAME) AREA=$(AREA) DATE_NUM=$(DATE_NUM) VALUE_1E6_STR=$(VALUE_1E6) \
	CONSUMER=$(CONSUMER) FORWARDER=$(FORWARDER) \
	FOUNDRY_DISABLE_INTERACTIVE=1 \
	forge script script/SendReportDemo.s.sol:SendReportDemo \
	  --rpc-url $(RPC_URL) --private-key $(PK) --broadcast


relay-json: ensure-consumer ensure-forwarder ensure-pk
	@if [ ! -f "$(PAYLOAD_PATH)" ]; then \
		echo "Payload not found: $(PAYLOAD_PATH)"; \
		echo "Run CRE simulation to generate it (or set PAYLOAD_PATH=...)"; \
		exit 1; \
	fi
	PAYLOAD_PATH=$(PAYLOAD_PATH) CONSUMER=$(CONSUMER) FORWARDER=$(FORWARDER) \
	forge script script/RelayFromJson.s.sol:RelayFromJson \
	  --rpc-url $(RPC_URL) --private-key $(PK) --broadcast

read: ensure-consumer
	INDEX_ID=$$(cast keccak "$(INDEX_NAME)"); \
	AREA_ID=$$(cast keccak "$(AREA)"); \
	cast call $(CONSUMER) \
	  "commitments(bytes32,bytes32,uint32)(bytes32,int256,address,uint64)" \
	  $$INDEX_ID $$AREA_ID $(DATE_NUM) \
	  --rpc-url $(RPC_URL)


seed:
	@if [ -z "$(CONSUMER)" ]; then echo "Consumer not deployed yet"; exit 1; fi
	@echo "Seeding $(SEED_DAYS) days for areas: $(SEED_AREAS)"
	@for a in $(SEED_AREAS); do \
	  $(MAKE) _seed_one SEED_AREA=$$a; \
	done

_seed_one:
	@i=0; \
	while [ $$i -lt $(SEED_DAYS) ]; do \
	  DATE_NUM=$$(date -u -d "$$i day ago" +%Y%m%d); \
	  VALUE_1E6=$$(( 40000000 + $$i*123456 )); \
	  $(MAKE) report AREA=$(SEED_AREA) DATE_NUM=$$DATE_NUM VALUE_1E6=$$VALUE_1E6 || true; \
	  i=$$(( $$i + 1 )); \
	done


demo: deploy allow-sender
	@$(MAKE) report AREA=NO1 DATE_NUM=20260125 VALUE_1E6=42420000
	@$(MAKE) read   AREA=NO1 DATE_NUM=20260125


clean:
	forge clean

simulate:
	@cd $(CRE_DIR) && ./run_workflow_and_capture.sh out


simulate-request: ensure-registry
	@if [ -z "$(REQUEST_ID)" ]; then \
		echo "Missing REQUEST_ID. Example: make simulate-request REQUEST_ID=0"; \
		exit 1; \
	fi
	@cd $(CRE_DIR) && ./run_request_and_capture.sh "$(REQUEST_ID)" "$(REGISTRY)" "$(RPC_URL)" "out" demo


frontend-env: ensure-consumer ensure-forwarder ensure-registry ensure-factory
	@echo "VITE_ANVIL_CONSUMER_ADDRESS=$(CONSUMER)"
	@echo "VITE_ANVIL_FORWARDER_ADDRESS=$(FORWARDER)"
	@echo "VITE_ANVIL_REGISTRY_ADDRESS=$(REGISTRY)"
	@echo "VITE_ANVIL_FACTORY_ADDRESS=$(FACTORY)"


option-create: ensure-pk
	INDEX_ID=$$(cast keccak "NORDPOOL_DAYAHEAD_AVG_V1"); \
	AREA_ID=$$(cast keccak "$(AREA)"); \
	PREMIUM_WEI=$$(cast --to-wei $(PREMIUM_ETH) ether); \
	PAYOUT_WEI=$$(cast --to-wei $(PAYOUT_ETH) ether); \
	cast send $(FACTORY) \
	  "createOption(address,bytes32,bytes32,uint32,int256,uint8,uint256,uint64)(address)" \
	  $(CONSUMER) $$INDEX_ID $$AREA_ID $(DATE_NUM) $(STRIKE_1E6) $(DIR) $$PREMIUM_WEI $(BUY_DEADLINE) \
	  --value $$PAYOUT_WEI \
	  --rpc-url $(RPC_URL) --private-key $(PK)