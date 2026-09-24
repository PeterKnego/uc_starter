# The one entry point — for you, your agent and CI. `make help` lists targets.
include uc-app.env
UC_VERSION := $(shell cat UC_VERSION)
MSRV := 1.89.0
export APP_NAME APP_ID FSM_NAME BASE_PORT

.DEFAULT_GOAL := help
.PHONY: help next bins build up down status restart-services demo kill-leader test test-cluster lint check todo done skip \
        diffreplay corpus upgrade-check snapshot-drill observe upgrade-drill package uc-upgrade

help: ## this list
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | sed 's/:.*## /\t/' | expand -t22

next: ## where am I on WHAT-NEXT.md? (agents: scripts/next.sh --json)
	@scripts/next.sh
bins: ## download + verify the ultima_cluster binaries for UC_VERSION
	@scripts/fetch-uc.sh
build: ## build the service and client (release)
	cargo build --release
up: build ## start 3 nodes + 3 services + 3 gateways (FRESH=1 wipes state)
	scripts/cluster.sh up $(if $(FRESH),--fresh)
down: ## stop the local cluster
	scripts/cluster.sh down
status: ## uc2ctl status on every node
	scripts/cluster.sh status
restart-services: build ## restart only your service after a rebuild
	scripts/cluster.sh restart-services
demo: ## run scripts/demo.sh against the gateways
	scripts/demo.sh
kill-leader: ## the failover exercise
	scripts/kill-leader.sh
test: ## unit + determinism + snapshot tests
	cargo test
test-cluster: build ## the 3-node smoke (spawns processes)
	cargo test --release --features cluster-tests --test cluster -- --nocapture
lint: ## fmt + clippy + MSRV clippy + determinism grep
	cargo fmt --check
	cargo clippy --all-targets -- -D warnings
	CARGO_TARGET_DIR=target/msrv cargo +$(MSRV) clippy --all-targets --locked -- -D warnings
	scripts/lint-determinism.sh --all
check: test lint ## test + lint, and record it for the tutor
	@scripts/stamp.sh check
todo: ## the TODO(app) markers left
	@grep -rn 'TODO(app)' src tests scripts docs WHAT-NEXT.md 2>/dev/null || echo "no TODO(app) markers left"
done: ## record a step the repo cannot show: make done STEP=concepts
	@scripts/progress.sh done $(STEP)
skip: ## deliberately skip a step: make skip STEP=snapshots
	@scripts/progress.sh skip $(STEP)
