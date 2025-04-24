# Cursor Rules Documentation

This document summarizes all Cursor rules used in this project. Each rule is
located in `.cursor/rules/` and governs a specific aspect of code quality,
structure, or workflow.

- When adding or updating a rule, update this file with a brief description.
- Rules are enforced by pre-commit hooks and CI.

## Rule List

- **cold-start.mdc**: Document and manage all manual steps required for cold
  start (initial deployment) of a system
- **nixos-commits.mdc**: Guidelines for NixOS configuration commits, including
  commit message standards and documentation requirements
- **secrets-management.mdc**: Standards for managing secrets with git-secret in
  the NixOS configuration
- **project-structure.mdc**: Standards for maintaining project structure
  documentation
- **rules.mdc**: Standards for placing Cursor rule files in the correct
  directory
- **markdown-standards.mdc**: Standards for authoring Markdown files that
  conform to the project's linting requirements

For more information on each rule, see the corresponding file in
`.cursor/rules/`.
