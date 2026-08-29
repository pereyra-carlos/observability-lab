#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
CHART_VERSION=1.24.4
HERE="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null

helm upgrade --install tempo grafana/tempo \
  --version "$CHART_VERSION" \
  --namespace "$NS" \
  --values "$HERE/tempo/values.yaml" \
  --wait --timeout 8m

echo
kubectl -n "$NS" get pods -l app.kubernetes.io/name=tempo
