# Paths
FLAKE_URI := .#skaia
NIXOS_DIR := /etc/nixos

# Default Target
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  edit       - Change permissions and open the editor"
	@echo "  lock       - Restore root permissions for /etc/nixos"
	@echo "  rebuild    - Rebuild the NixOS system configuration"
	@echo "  switch     - Rebuild and apply the configuration"
	@echo "  dry-run    - Test the configuration without applying changes"
	@echo "  check      - Lint the configuration using nix fmt"

.PHONY: edit
edit: ## Temporarily give user write access and open the editor
	sudo chown -R $(USER) $(NIXOS_DIR)
	code $(NIXOS_DIR)  # Replace `code` with `cursor` or your preferred editor

.PHONY: lock
lock: ## Restore root permissions for /etc/nixos
	sudo chown -R root $(NIXOS_DIR)

.PHONY: rebuild
rebuild: ## Rebuild the NixOS system configuration
	sudo nixos-rebuild build --flake $(NIXOS_DIR)

.PHONY: switch
switch: ## Rebuild and apply the NixOS configuration
	sudo nixos-rebuild switch --flake $(FLAKE_URI)

.PHONY: switch-explicit
switch-explicit:
	sudo nixos-rebuild switch --flake $(NIXOS_DIR)#skaia

.PHONY: dry-run
dry-run: ## Test the configuration without applying changes
	sudo nixos-rebuild dry-run --flake $(NIXOS_DIR)

.PHONY: check
check: ## Lint the configuration files using nix fmt
	nix fmt $(NIXOS_DIR)
