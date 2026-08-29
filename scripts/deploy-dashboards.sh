#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
CHART_VERSION=3.8.0
HERE="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add opensearch https://opensearch-project.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo update opensearch >/dev/null

"$HERE/scripts/bootstrap-secrets.sh"
"$HERE/scripts/ensure-os-users.sh"

helm upgrade --install opensearch-dashboards opensearch/opensearch-dashboards \
  --version "$CHART_VERSION" \
  --namespace "$NS" \
  --values "$HERE/opensearch/dashboards-values.yaml" \
  --wait --timeout 8m

echo
kubectl -n "$NS" get pods -l app.kubernetes.io/instance=opensearch-dashboards
