#!/usr/bin/env zsh

# Get the current (focused) workspace name using swaymsg and jq.
current_workspace=$(swaymsg -t get_workspaces -r | jq -r 'map(select(.focused))[0].name')

# Extract the numeric prefix from the current workspace name.
# This should work whether the name is "3" or already "3: something".
if [[ $current_workspace =~ ^([0-9]+) ]]; then
  prefix=${match[1]}
else
  echo "Unable to determine workspace number. Aborting."
  exit 1
fi

# Prompt for a new workspace name using wofi.
new_name=$(wofi --dmenu --prompt 'New workspace name: ')

# If a name was given, rename the workspace while
# preserving the numeric prefix.
if [[ -n "$new_name" ]]; then
  new_workspace_name="${prefix}: ${new_name}"
  swaymsg "rename workspace to \"$new_workspace_name\""
fi
