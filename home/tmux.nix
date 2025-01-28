{ config, pkgs, ... }:

{
  # TODO: for plugins, see:
  # https://haseebmajid.dev/posts/2023-07-10-setting-up-tmux-with-nix-home-manager/
  programs.tmux = {
    enable = true;

    shell = "${pkgs.zsh}/bin/zsh";

    historyLimit = 100000;

    terminal = "tmux-256color";

    # Mouse support
    mouse = true;

    extraConfig = ''
      # Aesthetics
      set-option -g status-bg colour235  # base02
      set-option -g status-fg colour136  # yellow

      # Remap prefix to Ctrl-a
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix

      # Create new named window with prompt
      bind-key C command-prompt -p "Name of new window: " "new-window -n '%%'"

      # Easy pane switching with Alt + Arrow keys
      bind -n M-Left select-pane -L
      bind -n M-Right select-pane -R
      bind -n M-Up select-pane -U
      bind -n M-Down select-pane -D

      # Open new panes in the current working directory
      bind - split-window -v -c "#{pane_current_path}"
      bind | split-window -h -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Set absolute pane width to 80 columns
      bind / resize-pane -x 80

      # Force a reload of the tmux configuration
      unbind r
      bind r source-file ~/.tmux.conf \; display-message "Config reloaded..."

      # Enable activity monitoring
      set -g visual-activity off
      setw -g monitor-activity on

      # Use Emacs-style key bindings in copy mode
      setw -g mode-keys emacs

      # Copy to system clipboard using xclip (adjust if using Wayland or another clipboard manager)
      bind-key -T copy-mode-emacs C-w send-keys -X copy-pipe-and-cancel "wl-copy"
      bind-key -T copy-mode-emacs MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "wl-copy"
    '';
  };
}
