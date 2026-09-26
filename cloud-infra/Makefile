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
# Every target here has a cloud- name (AGENTS.md rule 9): bare `make destroy`
# run from inside cloud-infra/ matches no target. CLOUD_INFRA_MAKE=1 is
# exported to every recipe's subshell (the bare `export` below exports all
# make variables); the scripts refuse to run without it (common.sh, require_make).
CLOUD_INFRA_MAKE := 1
export

TF     := terraform -chdir=terraform
TFVARS := $(CURDIR)/terraform.tfvars
S      := scripts
DURATION ?= 10
INFLIGHT ?= 32
LINES    ?= 40

.PHONY: cloud-env-show cloud-preflight cloud-up cloud-deploy cloud-test cloud-bench cloud-status cloud-logs cloud-destroy cloud-oneshot cloud-inventory

cloud-env-show:   ; @$(S)/env-show.sh
cloud-preflight:  ; @$(S)/preflight.sh
cloud-inventory:  ; @$(S)/inventory.sh

cloud-up: cloud-preflight
	$(TF) init -input=false >/dev/null
	$(TF) apply -auto-approve -input=false -var-file=$(TFVARS)
	$(S)/inventory.sh
	$(S)/deploy.sh

cloud-deploy: cloud-preflight
	$(S)/fsm-guard.sh
	$(S)/deploy.sh --restart

cloud-test:    ; $(S)/test.sh
cloud-bench:   ; $(S)/bench.sh $(DURATION) $(INFLIGHT)
cloud-status:  ; @$(S)/status.sh
cloud-logs:    ; @$(S)/logs.sh "$(HOST)" "$(PROC)" "$(LINES)"
cloud-destroy: ; $(S)/destroy.sh

cloud-oneshot:
	$(MAKE) cloud-up && $(MAKE) cloud-test; rc=$$?; $(MAKE) cloud-destroy; exit $$rc
