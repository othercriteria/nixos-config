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

      "pvc" = "sudo protonvpn c -f";
      "pvd" = "sudo protonvpn d";
      "pvs" = "protonvpn s";

      # These are only relevant on hosts that have k3s installed
      # TODO: refactor!
      h = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm";
      k = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl";
    };

    history = {
      size = 100000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initExtra = builtins.concatStringsSep "\n" [
      (builtins.readFile ../assets/p10k.zsh)
      (builtins.readFile ../assets/nix-direnv.zsh)
      "export EDITOR=\"emacs -nw\""
    ];

    zplug = {
      enable = true;
      plugins = [
        { name = "romkatv/powerlevel10k"; tags = [ "as:theme" "depth:1" ]; }
      ];
    };
  };
}
