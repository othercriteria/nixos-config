# Paths
LOCAL_DIR := $(shell pwd)
NIXOS_DIR := /etc/nixos

# Default Target
.DEFAULT_GOAL := help

.PHONY: help apply copy-to-system dry-run check init-security scan-secrets check-all rollback list-generations flake-update flake-restore

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

flake-update: ## Update the flake
	sudo nix flake update
	@echo "Note: Use 'make flake-restore' to undo this update if needed"

flake-restore: ## Restore flake.lock to last committed version
	git restore flake.lock
	@echo "Restored flake.lock to last committed version"

copy-to-system: ## Copy local configuration to /etc/nixos
	sudo cp -r $(LOCAL_DIR)/* $(NIXOS_DIR)/

apply: copy-to-system ## Apply the configuration from local directory
	sudo nixos-rebuild switch --flake $(NIXOS_DIR)#skaia

dry-run: copy-to-system ## Test the configuration without applying changes
	sudo nixos-rebuild dry-run --flake $(NIXOS_DIR)

check: ## Lint the configuration files using nix fmt and markdownlint
	nixpkgs-fmt .
	markdownlint "**/*.md"

init-security: ## Initialize security tools
	git secret init
	detect-secrets scan > .secrets.baseline
	pre-commit install

scan-secrets: ## Scan for secrets in the codebase
	detect-secrets scan
	gitleaks detect --verbose --no-git

check-all: check scan-secrets ## Run all checks
	pre-commit run --all-files

rollback: ## Rollback to the previous generation
	sudo nixos-rebuild switch --rollback
	@echo "System rolled back to previous generation"

list-generations: ## List all system generations
	sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
