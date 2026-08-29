{ config, pkgs, ... }:

{
  # Home-manager writes XDG (`~/.config/tmux/tmux.conf`). Older tmux
  # sessions still have `prefix-r` bound to `source-file ~/.tmux.conf`,
  # and some tools look there first. Keep both paths as the same file.
  home.file.".tmux.conf".source =
    config.xdg.configFile."tmux/tmux.conf".source;

  programs.tmux = {
    enable = true;

    shell = "${pkgs.zsh}/bin/zsh";

    historyLimit = 100000;

    terminal = "tmux-256color";

    # Mouse support
    mouse = true;

    extraConfig = ''
      # Same drab chrome as Sway's unfocused title bar / Waybar.
      set-option -g status-style "bg=#222222,fg=#888888"
      set-option -g window-status-current-style "bg=#5f676a,fg=#dddddd"
      set-option -g pane-border-style "fg=#333333"
      set-option -g pane-active-border-style "fg=#5f676a"
      set-option -g message-style "bg=#222222,fg=#dddddd"
      set-option -g mode-style "bg=#5f676a,fg=#dddddd"

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
      bind r source-file ${config.xdg.configHome}/tmux/tmux.conf \; display-message "Config reloaded..."

      # Enable activity monitoring
      set -g visual-activity off
      setw -g monitor-activity on

      # Use Emacs-style key bindings in copy mode
      setw -g mode-keys emacs

      # Copy to the Wayland clipboard
      bind-key -T copy-mode-emacs C-w send-keys -X copy-pipe-and-cancel "${pkgs.wl-clipboard}/bin/wl-copy"
      bind-key -T copy-mode-emacs MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${pkgs.wl-clipboard}/bin/wl-copy"
    '';
  };
}
