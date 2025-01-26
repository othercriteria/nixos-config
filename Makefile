# Paths
FLAKE_URI := .#skaia
NIXOS_DIR := /etc/nixos

# Default Target
.DEFAULT_GOAL := help

.PHONY: help edit lock rebuild switch switch-explicit dry-run check init-security scan-secrets check-all

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

edit: ## Temporarily give user write access and open the editor
	sudo chown -R $(USER) $(NIXOS_DIR)
	code $(NIXOS_DIR)  # Replace `code` with `cursor` or your preferred editor

lock: ## Restore root permissions for /etc/nixos
	sudo chown -R root $(NIXOS_DIR)

rebuild: ## Rebuild the NixOS system configuration
	sudo nixos-rebuild build --flake $(NIXOS_DIR)

switch: ## Rebuild and apply the NixOS configuration
	sudo nixos-rebuild switch --flake $(FLAKE_URI)

switch-explicit: ## Switch using explicit flake path
	sudo nixos-rebuild switch --flake $(NIXOS_DIR)#skaia

dry-run: ## Test the configuration without applying changes
	sudo nixos-rebuild dry-run --flake $(NIXOS_DIR)

check: ## Lint the configuration files using nix fmt
	nix fmt $(NIXOS_DIR)

init-security: ## Initialize security tools
	git secret init
	detect-secrets scan > .secrets.baseline
	pre-commit install

scan-secrets: ## Scan for secrets in the codebase
	detect-secrets scan

check-all: check scan-secrets ## Run all checks
	pre-commit run --all-files
