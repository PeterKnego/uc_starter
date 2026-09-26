# cloud-infra — this app on three cloud hosts. Top-level `make cloud-*` targets
# run these; README.md here explains setup. Every target that creates,
# changes or destroys hosts is asked for first (AGENTS.md, hard rule 9).

# Credentials from a gitignored .env (KEY=value, bare values). make keeps
# surrounding quotes literally, so strip them from the known variables.
-include .env
_ENV_CREDS := HCLOUD_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE GOOGLE_PROJECT GOOGLE_APPLICATION_CREDENTIALS
# Only variables that are set: an exported empty AWS_PROFILE would confuse the provider.
$(foreach v,$(_ENV_CREDS),$(if $($(v)),$(eval $(v) := $$(patsubst "%",%,$$($(v))))))

include ../uc-app.env
OWNER := $(shell printf '%s-%s' '$(APP_NAME)' "$${USER:-dev}" | tr 'A-Z_.' 'a-z--' | cut -c1-40)
TF_VAR_owner ?= $(OWNER)
TF_VAR_app_name := $(APP_NAME)
TF_VAR_base_port := $(BASE_PORT)
export

TF     := terraform -chdir=terraform
TFVARS := $(CURDIR)/terraform.tfvars
S      := scripts
DURATION ?= 10
INFLIGHT ?= 32
LINES    ?= 40

.PHONY: env-show preflight up deploy test bench status logs destroy oneshot inventory

env-show:   ; @$(S)/env-show.sh
preflight:  ; @$(S)/preflight.sh
inventory:  ; @$(S)/inventory.sh

up: preflight
	$(TF) init -input=false >/dev/null
	$(TF) apply -auto-approve -input=false -var-file=$(TFVARS)
	$(S)/inventory.sh
	$(S)/deploy.sh

deploy: preflight
	$(S)/fsm-guard.sh
	$(S)/deploy.sh --restart

test:    ; $(S)/test.sh
bench:   ; $(S)/bench.sh $(DURATION) $(INFLIGHT)
status:  ; @$(S)/status.sh
logs:    ; @$(S)/logs.sh "$(HOST)" "$(PROC)" "$(LINES)"
destroy: ; $(S)/destroy.sh

oneshot:
	$(MAKE) up && $(MAKE) test; rc=$$?; $(MAKE) destroy; exit $$rc
