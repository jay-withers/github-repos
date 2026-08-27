.DEFAULT_GOAL := help

.PHONY: help install lint init fmt validate plan apply destroy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install pre-commit hooks (run once after cloning)
	pre-commit install
	pre-commit install --hook-type commit-msg

lint: ## Run all pre-commit hooks against every file
	pre-commit run --all-files

init: ## terraform init (see terraform/README.md for required auth)
	terraform -chdir=terraform init

fmt: ## terraform fmt -recursive
	terraform -chdir=terraform fmt -recursive

validate: init ## terraform init + validate
	terraform -chdir=terraform validate

plan: init ## terraform init + plan
	terraform -chdir=terraform plan

apply: init ## terraform init + apply
	terraform -chdir=terraform apply

destroy: init ## terraform init + destroy
	terraform -chdir=terraform destroy
