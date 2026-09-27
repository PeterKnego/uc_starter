# The one entry point — for you, your agent and CI. `make help` lists targets.
include uc-app.env
UC_VERSION := $(shell cat UC_VERSION)
MSRV := 1.89.0
export APP_NAME APP_ID FSM_NAME BASE_PORT

.DEFAULT_GOAL := help
.PHONY: help next bins build up down status restart-services demo kill-leader test test-cluster lint check todo done skip \
        diffreplay corpus upgrade-check snapshot-drill observe upgrade-drill package uc-upgrade \
        cloud-plan cloud-up cloud-deploy cloud-test cloud-bench cloud-status cloud-logs cloud-destroy cloud-oneshot

help: ## this list
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | sed 's/:.*## /\t/' | expand -t22

next: ## where am I on TUTORIAL.md? (agents: scripts/next.sh --json)
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
	cargo test --release --features cluster-tests --test cluster -- --nocapture --test-threads=1
lint: ## fmt + clippy + MSRV clippy + determinism grep
	cargo fmt --check
	cargo clippy --all-targets -- -D warnings
	CARGO_TARGET_DIR=target/msrv cargo +$(MSRV) clippy --all-targets --locked -- -D warnings
	scripts/lint-determinism.sh --all
check: test lint ## test + lint, and record it for the tutor
	@scripts/stamp.sh check
todo: ## the TODO(app) markers left
	@grep -rn 'TODO(app)' src tests scripts docs TUTORIAL.md 2>/dev/null || echo "no TODO(app) markers left"
done: ## record a step the repo cannot show: make done STEP=concepts
	@scripts/progress.sh done $(STEP)
skip: ## deliberately skip a step: make skip STEP=observe
	@scripts/progress.sh skip $(STEP)
diffreplay: ## install uc2-diffreplay for UC_VERSION into .uc/cargo
	cargo install uc_diffreplay --version $(UC_VERSION) --locked --root .uc/cargo
corpus: ## capture a diff-replay corpus + keep the old binary (before changing code)
	scripts/corpus.sh
upgrade-check: ## diff-replay the corpus through old vs new builds
	scripts/upgrade-check.sh
snapshot-drill: ## snapshot, kill a service, watch it rebuild
	scripts/snapshot-drill.sh
observe: ## health, readiness and key metrics on every node
	scripts/observe.sh
upgrade-drill: ## the pinned upgrade on the local cluster (asks first: one-way door)
	scripts/upgrade-drill.sh $(if $(RESUME),--resume)
package: ## deploy bundle: make package HOSTS=ip0,ip1,ip2
	HOSTS=$(HOSTS) scripts/package.sh
uc-upgrade: ## move to another UC release: make uc-upgrade VERSION=x
	scripts/uc-upgrade.sh $(VERSION)
cloud-plan: ## what cloud-up would create, change or destroy (read-only)
	@$(MAKE) -s -C cloud-infra cloud-plan
cloud-up: ## 3 cloud hosts + deploy (billable; asks first) — cloud-infra/README.md
	$(MAKE) -C cloud-infra cloud-up
cloud-deploy: ## rebuild + redeploy the app, same FSM_VERSION only
	$(MAKE) -C cloud-infra cloud-deploy
cloud-test: ## demo, MTU and a host failover on the cloud cluster
	$(MAKE) -C cloud-infra cloud-test
cloud-bench: ## load it: make cloud-bench DURATION=10 INFLIGHT=32
	$(MAKE) -C cloud-infra cloud-bench DURATION=$(or $(DURATION),10) INFLIGHT=$(or $(INFLIGHT),32)
cloud-status: ## hosts, uptime vs ttl_hours, leader, /readyz
	@$(MAKE) -s -C cloud-infra cloud-status
cloud-logs: ## make cloud-logs HOST=0 PROC=node|service|gateway
	@$(MAKE) -s -C cloud-infra cloud-logs HOST=$(HOST) PROC=$(PROC) LINES=$(or $(LINES),40)
cloud-destroy: ## tear the cloud hosts down
	$(MAKE) -C cloud-infra cloud-destroy
cloud-oneshot: ## up, test, destroy (destroys on Ctrl-C too)
	$(MAKE) -C cloud-infra cloud-oneshot
