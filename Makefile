# Paths
LOCAL_DIR := $(shell pwd)
NIXOS_DIR := /etc/nixos

# Files to sync (explicit inclusion)
# TODO: Add other private-assets paths as needed
SYNC_PATHS := \
  flake.nix \
  flake.lock \
  hosts \
  modules \
  home \
  assets \
  private-assets/fonts \
  secrets

# Default Target
.DEFAULT_GOAL := help

# Check if TMPDIR exists and is accessible
ifeq ($(shell test -d "$(TMPDIR)" && echo yes || echo no),no)
  export TMPDIR := /tmp
endif

.PHONY: help check init-security scan-secrets check-all test test-observability demo rollback list-generations flake-update flake-restore apply-host sync-to-system reveal-secrets init update add-private-assets add-gitops-veil snapshot-gitops check-unbound build-host check-unbound-built

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

test: ## Run all NixOS integration tests (requires kvm)
	nix flake check

test-observability: ## Run the observability stack integration test
	nix build .#checks.x86_64-linux.observability --print-build-logs

demo: ## Build and run the demo VM (observability stack showcase)
	@# Check if demo VM is already running
	@if pgrep -f "qemu-system.*-name demo" > /dev/null 2>&1; then \
		echo "⚠️  A demo VM appears to be already running!"; \
		echo "   Stop it first (Ctrl+A, X in QEMU) or run: make demo-stop"; \
		exit 1; \
	fi
	@echo "Building demo VM..."
	nixos-rebuild build-vm --flake .#demo
	@# Check if disk image exists and warn about stale state
	@if [ -f demo.qcow2 ]; then \
		echo ""; \
		echo "ℹ️  Existing disk image found (demo.qcow2)"; \
		echo "   VM will reuse previous state. Run 'make demo-clean' for fresh start."; \
	fi
	@echo ""
	@echo "Starting demo VM with port forwarding (offset to avoid conflicts):"
	@echo "  Prometheus: http://localhost:19090"
	@echo "  Grafana:    http://localhost:13000"
	@echo "  Loki:       http://localhost:13100"
	@echo ""
	@echo "Login: demo / demo"
	@echo "Press Ctrl+A then X to exit QEMU"
	@echo ""
	./result/bin/run-demo-vm

demo-clean: ## Remove demo VM disk image (forces fresh start)
	@if [ -f demo.qcow2 ]; then \
		rm -f demo.qcow2; \
		echo "Removed demo.qcow2 - next 'make demo' will start fresh"; \
	else \
		echo "No demo.qcow2 found"; \
	fi

demo-stop: ## Stop any running demo VM
	@pid=$$(pgrep -f "qemu-system.*-name demo" 2>/dev/null); \
	if [ -n "$$pid" ]; then \
		echo "Stopping demo VM (PID $$pid)..."; \
		(kill $$pid 2>/dev/null &); \
		sleep 1; \
		if pgrep -f "qemu-system.*-name demo" > /dev/null 2>&1; then \
			echo "VM still running, sending SIGKILL..."; \
			(kill -9 $$pid 2>/dev/null &); \
			sleep 1; \
		fi; \
		echo "Demo VM stopped"; \
	else \
		echo "No demo VM running"; \
	fi

demo-fresh: demo-stop demo-clean ## Stop, clean, and run demo VM with fresh state
	@$(MAKE) demo

demo-status: ## Show demo VM status and diagnostics
	@echo "Demo VM Status"
	@echo "=============="
	@if pgrep -f "qemu-system.*-name demo" > /dev/null 2>&1; then \
		echo "VM: Running (PID $$(pgrep -f 'qemu-system.*-name demo'))"; \
		echo ""; \
		echo "Port forwarding (from host):"; \
		echo "  Prometheus: http://localhost:19090"; \
		echo "  Grafana:    http://localhost:13000"; \
		echo "  Loki:       http://localhost:13100"; \
	else \
		echo "VM: Not running"; \
	fi
	@echo ""
	@if [ -f demo.qcow2 ]; then \
		echo "Disk image: demo.qcow2 ($$(du -h demo.qcow2 | cut -f1))"; \
		echo "  Last modified: $$(stat -c '%y' demo.qcow2 | cut -d. -f1)"; \
	else \
		echo "Disk image: None (will be created on first run)"; \
	fi
	@echo ""
	@if [ -L result ]; then \
		echo "Build: $$(readlink result)"; \
	else \
		echo "Build: Not built (run 'make demo' first)"; \
	fi

rollback: ## Rollback to the previous generation
	sudo nixos-rebuild switch --rollback
	@echo "System rolled back to previous generation"

list-generations: ## List recent system generations
	sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -n 10

sync-to-system: reveal-secrets ## Sync changes to /etc/nixos
	@echo "Preparing to sync changes to $(NIXOS_DIR)..."
	@success=true; \
	for path in $(SYNC_PATHS); do \
		echo "Syncing $$path..."; \
		if [ -e "$$path" ]; then \
			if [ -d "$$path" ]; then \
				sudo mkdir -p "$(NIXOS_DIR)/$$path" && \
				sudo rsync -a --delete --exclude '*.secret' "$$path/" "$(NIXOS_DIR)/$$path" || success=false; \
			else \
				sudo mkdir -p "$(NIXOS_DIR)/$$(dirname $$path)" && \
				sudo rsync -a --delete --exclude '*.secret' "$$path" "$(NIXOS_DIR)/$$path" || success=false; \
			fi; \
		else \
			echo "Warning: $$path does not exist"; \
			success=false; \
		fi; \
	done; \
	if [ "$$success" = true ]; then \
		echo "Sync completed successfully."; \
	else \
		echo "Error: Sync failed. No changes were applied."; \
		exit 1; \
	fi

apply-host: sync-to-system ## Apply configuration for specific host
	@if [ -z "$(HOST)" ]; then \
		echo "Error: HOST variable not set. Usage: make apply-host HOST=skaia"; \
		exit 1; \
	fi
	@CURRENT_HOST=$$(hostname); \
	if [ "$$CURRENT_HOST" != "$(HOST)" ]; then \
		echo ""; \
		echo "⚠️  WARNING: Hostname mismatch!"; \
		echo "   Current host: $$CURRENT_HOST"; \
		echo "   Target config: $(HOST)"; \
		echo ""; \
		read -p "Are you sure you want to apply $(HOST) config to $$CURRENT_HOST? [y/N] " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "Aborted."; \
			exit 1; \
		fi; \
	fi
	sudo nixos-rebuild switch --flake $(NIXOS_DIR)#$(HOST)

# Restored targets
init: init-security ## Initialize repository
	git lfs install
	git lfs pull

update: ## Update submodules to latest
	git submodule update --remote
	git lfs pull

# Submodule targets
add-private-assets: ## Initialize private-assets submodule (fonts, etc.)
	@if git config -f .gitmodules --get-regexp '^submodule\.private-assets\.url' >/dev/null 2>&1; then \
		echo "Submodule 'private-assets' already configured; initializing/updating..."; \
		git submodule update --init --recursive private-assets; \
	else \
		echo "Adding submodule 'private-assets'..."; \
		git submodule add git@github.com:othercriteria/private-assets.git private-assets; \
		git submodule update --init --recursive private-assets; \
	fi
	@git lfs pull --include "private-assets/**"

add-gitops-veil: ## Initialize gitops-veil submodule (veil cluster GitOps)
	@if git config -f .gitmodules --get-regexp '^submodule\.gitops-veil\.url' >/dev/null 2>&1; then \
		echo "Submodule 'gitops-veil' already configured; initializing/updating..."; \
		git submodule update --init --recursive gitops-veil; \
	else \
		echo "Adding submodule 'gitops-veil'..."; \
		git submodule add git@github.com:othercriteria/gitops-veil.git gitops-veil; \
		git submodule update --init --recursive gitops-veil; \
	fi

snapshot-gitops: ## Sync public GitOps manifests to flux-snapshot/ (illustrative)
	@echo "Syncing gitops-veil/public/ to flux-snapshot/veil/public/..."
	@if [ -d gitops-veil/public ]; then \
		mkdir -p flux-snapshot/veil; \
		rsync -a --delete gitops-veil/public/ flux-snapshot/veil/public/; \
		echo "Snapshot complete. Remember: flux-snapshot/ is illustrative, not authoritative."; \
	else \
		echo "Error: gitops-veil/public/ not found. Run 'make add-gitops-veil' first."; \
		exit 1; \
	fi

build-host: ## Build system closure for HOST without switching (uses workspace flake)
	@if [ -z "$(HOST)" ]; then \
		echo "Error: HOST variable not set. Usage: make build-host HOST=skaia"; \
		exit 1; \
	fi
	@CURRENT_HOST=$$(hostname); \
	if [ "$$CURRENT_HOST" != "$(HOST)" ]; then \
		echo "Note: Building $(HOST) config on $$CURRENT_HOST (cross-host build)"; \
	fi
	nixos-rebuild build --flake .#$(HOST)

check-unbound: ## Validate generated unbound.conf with unbound-checkconf (HOST=skaia)
	@if [ -z "$(HOST)" ]; then HOST=skaia; fi; \
	OUT=$$(nix build --no-link --print-out-paths '.#nixosConfigurations.'$$HOST'.config.environment.etc."unbound/unbound.conf".source'); \
	nix shell nixpkgs#unbound -c unbound-checkconf $$OUT; \
	echo "unbound-checkconf passed for $$HOST"

check-unbound-built: ## Validate unbound.conf from a built closure (after build-host)
	@if [ -z "$(HOST)" ]; then HOST=skaia; fi; \
	if [ ! -e result ]; then \
		echo "Build first: make build-host HOST=$$HOST"; exit 1; \
	fi; \
	CFG=result/etc/unbound/unbound.conf; \
	if [ ! -f $$CFG ]; then \
		echo "No unbound.conf found in build output"; exit 1; \
	fi; \
	nix shell nixpkgs#unbound -c unbound-checkconf $$CFG; \
	echo "unbound-checkconf passed for built system $$HOST"
