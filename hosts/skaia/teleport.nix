{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault;
in
{
  # COLD START: Ensure router forwards TCP 3023 and 3024 to skaia before relying
  # on Teleport for external access. See docs/COLD-START.md for detailed steps.
  #
  # COLD START: Confirm DNS for teleport.valueof.info resolves to the public IP
  # of skaia (managed automatically via ddclient once configured).
  #
  # COLD START: After the service is running, create the initial Teleport admin
  # user with `sudo tctl users add <name> --roles=editor,access` and enroll
  # clients using `tsh login`.
  services.teleport = {
    enable = true;
    package = mkDefault pkgs.teleport_18;
    settings = {
      teleport = {
        nodename = "skaia";
        data_dir = "/var/lib/teleport";
        log = {
          output = "stderr";
          severity = "INFO";
        };
      };

      auth_service = {
        enabled = true;
        cluster_name = "residence-1";
      };

      proxy_service = {
        enabled = true;
        # Listen on the ports forwarded from the TP-Link router.
        listen_addr = "0.0.0.0:3023";
        tunnel_listen_addr = "0.0.0.0:3024";
        public_addr = "teleport.valueof.info:443";
        tunnel_public_addr = "valueof.info:3024";
        kube_listen_addr = "0.0.0.0:3026";
        kube_public_addr = "teleport.valueof.info:443";
        # Keep the HTTPS UI bound locally; nginx reverse-proxies to this port.
        web_listen_addr = "127.0.0.1:3080";
      };

      ssh_service = {
        enabled = true;
        labels = {
          role = "proxy";
          site = "residence-1";
        };
      };

      kubernetes_service = {
        enabled = true;
        listen_addr = "127.0.0.1:3027";
        kubeconfig_file = "/var/lib/teleport/kubeconfig/k3s.yaml";
        labels = {
          site = "residence-1";
          role = "k8s";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/teleport/kubeconfig 0750 root root -"
  ];

  systemd.services.teleport.preStart = lib.mkAfter ''
    tmpfile=$(${pkgs.coreutils}/bin/mktemp /run/k3s-kubeconfig.XXXXXX)
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml ${pkgs.kubectl}/bin/kubectl config view --raw > "$tmpfile"
    install -D -m 640 -o root -g root "$tmpfile" /var/lib/teleport/kubeconfig/k3s.yaml
    rm -f "$tmpfile"

    ${pkgs.gnused}/bin/sed -i 's/name: default/name: skaia/g' /var/lib/teleport/kubeconfig/k3s.yaml
    ${pkgs.gnused}/bin/sed -i 's/current-context: .*/current-context: skaia/' /var/lib/teleport/kubeconfig/k3s.yaml
    ${pkgs.gnused}/bin/sed -i 's/cluster: default/cluster: skaia/g' /var/lib/teleport/kubeconfig/k3s.yaml
    ${pkgs.gnused}/bin/sed -i 's/user: default/user: skaia/g' /var/lib/teleport/kubeconfig/k3s.yaml
  '';
}
