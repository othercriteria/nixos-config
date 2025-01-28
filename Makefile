# Paths
LOCAL_DIR := $(shell pwd)
NIXOS_DIR := /etc/nixos

# Files to sync (explicit inclusion)
SYNC_PATHS := \
  flake.nix \
  flake.lock \
  hosts \
  modules \
  home \
  assets \
  secrets

# Default Target
.DEFAULT_GOAL := help

.PHONY: help check init-security scan-secrets check-all rollback list-generations flake-update flake-restore apply-host dry-run-host sync-to-system force-sync-to-system reveal-secrets init update

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

reveal-secrets: ## Reveal git-secret encrypted files
	@if command -v git-secret > /dev/null; then \
		if [ -f .gitsecret/paths/mapping.cfg ]; then \
			echo "Revealing secrets..."; \
			git secret reveal -f; \
			echo "Setting secure permissions on revealed files..."; \
			while IFS= read -r file; do \
				if [ -f "$$file" ] && [[ ! "$$file" =~ \.secret$$ ]]; then \
					sudo chmod 600 "$$file"; \
					echo "Set 600 permissions for $$file"; \
				fi; \
			done < <(find secrets -type f -not -name "*.secret"); \
		else \
			echo "No git-secret files found."; \
		fi \
	else \
		echo "git-secret not installed. Skipping secret revelation."; \
	fi

flake-update: ## Update the flake
	sudo nix flake update
	@echo "Note: Use 'make flake-restore' to undo this update if needed"

flake-restore: ## Restore flake.lock to last committed version
	git restore flake.lock
	@echo "Restored flake.lock to last committed version"

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

list-generations: ## List recent system generations
	sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -n 10

sync-to-system: reveal-secrets ## Preview changes to be synced to /etc/nixos
	@echo "Previewing changes that would be made to $(NIXOS_DIR)..."
	@success=true; \
	for path in $(SYNC_PATHS); do \
		echo "Checking $$path..."; \
		if [ -e "$$path" ]; then \
			if [ -d "$$path" ]; then \
				sudo rsync -ainv --delete --exclude '*.secret' "$$path/" "$(NIXOS_DIR)/$$path" || success=false; \
			else \
				sudo rsync -ainv --delete --exclude '*.secret' "$$path" "$(NIXOS_DIR)/$$path" || success=false; \
			fi; \
		else \
			echo "Warning: $$path does not exist"; \
			success=false; \
		fi; \
	done; \
	if [ "$$success" = true ]; then \
		echo "Preview completed successfully. Run 'make force-sync-to-system' to apply."; \
	else \
		echo "Error: Some paths could not be previewed."; \
		exit 1; \
	fi

force-sync-to-system: reveal-secrets ## Force sync configuration to /etc/nixos
	@echo "Preparing to sync changes to $(NIXOS_DIR)..."
	@temp_dir=$$(mktemp -d); \
	success=true; \
	trap 'rm -rf "$$temp_dir"' EXIT; \
	for path in $(SYNC_PATHS); do \
		echo "Syncing $$path..."; \
		if [ -e "$$path" ]; then \
			if [ -d "$$path" ]; then \
				sudo rsync -aK --delete --exclude '*.secret' "$$path/" "$$temp_dir/$$path" || success=false; \
			else \
				sudo rsync -aK --delete --exclude '*.secret' "$$path" "$$temp_dir/$$path" || success=false; \
			fi; \
		else \
			echo "Error: $$path does not exist"; \
			success=false; \
			break; \
		fi; \
	done; \
	if [ "$$success" = true ]; then \
		echo "Staging successful, applying changes..."; \
		sudo rsync -aKvh --delete "$$temp_dir/" "$(NIXOS_DIR)/"; \
		echo "Setting secure permissions on secret files..."; \
		while IFS= read -r file; do \
			target_file="$(NIXOS_DIR)/$$file"; \
			if [ -f "$$target_file" ] && [[ ! "$$file" =~ \.secret$$ ]]; then \
				sudo chmod 600 "$$target_file"; \
				echo "Set 600 permissions for $$target_file"; \
			fi; \
		done < <(find secrets -type f -not -name "*.secret"); \
		echo "Sync completed successfully."; \
	else \
		echo "Error: Sync failed. No changes were applied."; \
		exit 1; \
	fi

dry-run-host: reveal-secrets ## Test configuration for specific host
	@if [ -z "$(HOST)" ]; then \
		echo "Error: HOST variable not set. Usage: make dry-run-host HOST=laptop"; \
		exit 1; \
	fi
	sudo nixos-rebuild dry-run --flake $(NIXOS_DIR)#$(HOST)

apply-host: force-sync-to-system ## Apply configuration for specific host
	@if [ -z "$(HOST)" ]; then \
		echo "Error: HOST variable not set. Usage: make apply-host HOST=laptop"; \
		exit 1; \
	fi
	sudo nixos-rebuild switch --flake $(NIXOS_DIR)#$(HOST)

init: init-security ## Initialize repository
	git submodule update --init --recursive
	git lfs install
	git lfs pull

update: ## Update submodules to latest
	git submodule update --remote
	git lfs pull
