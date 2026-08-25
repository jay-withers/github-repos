# CHECKS has no default here (unlike BRANCH) - it must stay unset/empty so
# that the recipe below passes an empty string through to protect-branch.sh,
# which supplies its own (newline-separated) default. A Make variable can't
# hold that default itself: GNU Make invokes a separate shell per recipe line,
# splitting on any raw newline in an expanded value - even one inside a quoted
# shell string - which would break the quoting in the recipe below.
BRANCH ?= main

.DEFAULT_GOAL := help

.PHONY: help install protect-branch lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install pre-commit hooks (run once after cloning)
	pre-commit install
	pre-commit install --hook-type commit-msg

protect-branch: ## Configure GitHub repo settings for a template-derived repo (auto-merge, branch protection) via gh CLI - override BRANCH/CHECKS if your repo's checks differ
	./scripts/protect-branch.sh "$(BRANCH)" "$(CHECKS)"

lint: ## Run all pre-commit hooks against every file
	pre-commit run --all-files
