{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      em = "emacs -nw";

      "tmux-join" = "tmux attach -t";
      "tmux-list" = "tmux list-sessions";
      "tmux-make" = "tmux new -s";
      "tmux-swap" = "tmux switch -t";

      h = "helm";
      k = "kubectl";
    };

    history = {
      size = 100000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initContent = builtins.concatStringsSep "\n" [
      (builtins.readFile ../assets/p10k.zsh)
      (builtins.readFile ../assets/nix-direnv.zsh)
      "export EDITOR=\"emacs -nw\""
      "if [ -f /etc/nixos/secrets/anthropic-2025-03-28-local-dev ]; then"
      "  export ANTHROPIC_API_KEY=\"$(cat /etc/nixos/secrets/anthropic-2025-03-28-local-dev)\""
      "fi"
    ];

    zplug = {
      enable = true;
      plugins = [
        { name = "romkatv/powerlevel10k"; tags = [ "as:theme" "depth:1" ]; }
      ];
    };
  };
}
