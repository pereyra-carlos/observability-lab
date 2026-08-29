#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
CHART_VERSION=10.5.15
HERE="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null

"$HERE/scripts/bootstrap-secrets.sh"

helm upgrade --install grafana grafana/grafana \
  --version "$CHART_VERSION" \
  --namespace "$NS" \
  --values "$HERE/grafana/values.yaml" \
  --wait --timeout 8m

NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo
echo "  http://${NODE}:${PORT}"
echo "  user admin, password: kubectl -n $NS get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d"
