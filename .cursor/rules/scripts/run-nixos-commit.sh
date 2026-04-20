#!/bin/bash

# Helper script for the nixos-commits rule to format and execute a git commit.

# Arguments:
# $1: type
# $2: concise description
# $3: detailed description (can be multi-line, "None" if not provided)
# $4: breaking changes (can be multi-line, "None" if not provided)
# $5: affected hosts (can be multi-line, "None" if not provided)

COMMIT_TYPE="$1"
CONCISE_DESCRIPTION="$2"
DETAILED_DESCRIPTION="$3"
BREAKING_CHANGES="$4"
AFFECTED_HOSTS="$5"

# Check if any files are staged
STAGED_FILES=$(git diff --cached --name-only)
if [ -z "$STAGED_FILES" ]; then
  echo "Error: No files staged for commit. Use git add to stage changes." >&2
  exit 1
fi
echo "Files to be committed (checked by run-nixos-commit.sh):" >&2
echo "$STAGED_FILES" >&2
echo "" >&2
echo "Summary of changes (checked by run-nixos-commit.sh):" >&2
git diff --cached --stat >&2
echo "" >&2

# Check for untracked .mdc files in .cursor/rules
# Assuming .cursor is in the project root. If not, this path needs adjustment.
UNTRACKED_RULES=$(git ls-files --others --exclude-standard .cursor/rules/*.mdc)
if [ -n "$UNTRACKED_RULES" ]; then
  echo "Error: Found untracked rule files. Please add them to git first:" >&2
  echo "$UNTRACKED_RULES" >&2
  exit 1
fi

# Check if STRUCTURE.md needs updating (only for adds/deletes/renames)
CHANGED_FILES=$(git diff --cached --name-only)
CHANGED_STATUS=$(git diff --cached --name-status --find-renames)
NEEDS_STRUCTURE_UPDATE=false

# Collect files that were Added, Deleted, or Renamed (new path)
STRUCT_PATHS=$(echo "$CHANGED_STATUS" | awk '
  /^A\t/ { print $2 }
  /^D\t/ { print $2 }
  /^R[0-9]+\t/ { print $3 }')

if [ -n "$STRUCT_PATHS" ]; then
  # Consider structural only if paths are within top-level structural areas
  echo "$STRUCT_PATHS" | grep -qE '^(modules/|hosts/|home/|flux/|assets/|private-assets/|secrets/|flake\.nix|Makefile|\.cursor/rules/.*\.mdc$)'
  if [ $? -eq 0 ]; then
    NEEDS_STRUCTURE_UPDATE=true
  fi
fi

if [ "$NEEDS_STRUCTURE_UPDATE" = true ] && ! echo "$CHANGED_FILES" | grep -q '^STRUCTURE\.md$'; then
  echo "Error: Structural changes detected but STRUCTURE.md not updated." >&2
  echo "Please update STRUCTURE.md or include it in the commit if changes affect project structure." >&2
  exit 1
fi

# Check consistency between pre-commit config and this rule
if echo "$CHANGED_FILES" | grep -q '\.pre-commit-config\.yaml$'; then
  echo "Note: Changes detected in .pre-commit-config.yaml." >&2
  echo "Remember to ensure consistency between pre-commit hooks and the nixos-commits rule." >&2
  echo "Consider reviewing .cursor/rules/nixos-commits.mdc if you've modified checks." >&2
fi

# Build the `git commit` invocation as an array so each logical section
# becomes exactly one -m argument. Git separates consecutive -m args with a
# blank line, which gives us the rule's template layout:
#
#   <type>: <concise description>
#
#   <body>
#
#   Breaking Changes:
#   - ...
#
#   Affected Hosts:
#   - ...
#
# Literal newlines inside a single -m are preserved verbatim, so multi-line
# body/bullet blocks render without the spurious blank lines that the old
# "one -m per line" approach produced.

# Treat "None" (literal) as "absent" -- the rule passes "None" for unused
# optional arguments.
is_present() {
  [[ -n "$1" && "$1" != "None" ]]
}

cmd=(git commit -m "$COMMIT_TYPE: $CONCISE_DESCRIPTION")

if is_present "$DETAILED_DESCRIPTION"; then
  cmd+=(-m "$DETAILED_DESCRIPTION")
fi

if is_present "$BREAKING_CHANGES"; then
  cmd+=(-m "Breaking Changes:
$BREAKING_CHANGES")
fi

if is_present "$AFFECTED_HOSTS"; then
  cmd+=(-m "Affected Hosts:
$AFFECTED_HOSTS")
fi

# Log what we're about to run. Use %q so embedded newlines/quotes survive the
# round trip into the user's terminal log.
{
  printf 'Executing:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
} >&2

exec "${cmd[@]}"
