# Veil Cluster: Plan and Progress

This document tracks rollout of the headless Kubernetes cluster "veil"
(`meteor-1..3`) and minimal refactors. Focus is on outstanding work and
validation.

## Status

- k3s HA control plane across `meteor-1..3` is healthy (3-member etcd)
- FluxCD bootstrapped in `flux-system`
- Core services installed via Flux:
  - MetalLB (L2, pool 192.168.0.220–239)
  - ingress-nginx (LoadBalancer)
  - kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- API readyz and etcd health verified
- MetalLB LoadBalancer assignment validated (`lb-test` at 192.168.0.222)

## Outstanding work

- [ ] Admin kubeconfig for `dlk` with `veil` context
- [ ] Baseline Grafana dashboards and alerting rules
- [ ] Runbooks (backups, upgrades)
- [ ] DNS move to `skaia` (host `veil.home.arpa`)
- [ ] Optional: migrate `skaia` to systemd-networkd
- [ ] Consider extracting `desktop-common` for workstation profiles

References:

- Cold start steps: `docs/COLD-START.md`
- Network/DNS details: `docs/residence-1/ADDRESSING.md`
- Flux manifests: `flux/`

## Validation plan

### Ingress functionality

- Deploy a simple echo app behind ingress and test HTTP routing:

```bash
kubectl create ns ingress-test || true
kubectl -n ingress-test create deployment hello \
  --image=nginxdemos/hello
kubectl -n ingress-test expose deployment hello --port=80
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello
  namespace: ingress-test
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello
            port:
              number: 80
EOF
# Determine ingress address via the ingress-nginx LoadBalancer IP
# From LAN: curl http://192.168.0.220/ (or the assigned IP)
```

- Clean up:

```bash
kubectl delete ns ingress-test
```

### Observability

- Verify Prometheus targets and Grafana access:

```bash
kubectl -n monitoring get pods
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-stack-grafana 3000:80
# Browser: http://localhost:3000 (default creds chart-dependent)
# Check Kubernetes/Nodes dashboard and alert rules
```

### Node drain and resilience

- Cordon and drain a control-plane node, verify service continuity:

```bash
kubectl cordon meteor-1
kubectl drain meteor-1 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes -o wide
kubectl get hr -A
# Check ingress and monitoring endpoints still respond
kubectl uncordon meteor-1
```

### Failure tests (physical)

- Ethernet pull:
  1. Unplug `meteor-1` for ~2 minutes
  1. Watch: `kubectl get nodes -w` and `kubectl get hr -A`
  1. Verify services remain reachable; expect etcd leader to move if needed
  1. Reconnect and confirm node returns to Ready

- Power-cycle:
  1. Power off `meteor-2`
  1. Verify control plane availability and service health
  1. Power on, confirm reconciliation and Ready state

## Post-setup (later)

- [ ] Admin kubeconfig for `dlk` with `veil` context

```bash
# on meteor-1
sudo cat /etc/rancher/k3s/k3s.yaml > /tmp/veil-kubeconfig
sed -i 's/127.0.0.1/192.168.0.121/' /tmp/veil-kubeconfig
scp meteor-1:/tmp/veil-kubeconfig ~/.kube/config-veil
kubectl --kubeconfig ~/.kube/config-veil config rename-context default veil
```

- [ ] Baseline Grafana dashboards and alerting rules
  - Import common Kubernetes dashboards
  - Configure Alertmanager receivers and routes

- [ ] Runbooks (backups, upgrades)
  - On-demand etcd snapshot:

    ```bash
    sudo k3s etcd-snapshot save --name on-demand-$(date +%F)
    ```

  - Rolling upgrades:

    ```bash
    kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
    # Rebuild host (NixOS), reboot, verify node Ready again
    kubectl uncordon <node>
    ```

## Open items

- Plan DNS move to `skaia` (host `veil.home.arpa`)
- Optional: migrate `skaia` to systemd-networkd later
- Consider extracting `desktop-common` for workstation profiles
