#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
CHART_VERSION=0.56.0
HERE="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add fluent https://fluent.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update fluent >/dev/null

PASS=$(kubectl -n "$NS" get secret opensearch-fluentbit -o jsonpath='{.data.password}' | base64 -d)
kubectl -n "$NS" create secret generic opensearch-fluentbit-env \
  --from-literal=OS_USER=fluentbit \
  --from-literal=OS_PASSWORD="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm upgrade --install fluent-bit fluent/fluent-bit \
  --version "$CHART_VERSION" \
  --namespace "$NS" \
  --values "$HERE/fluent-bit/values.yaml" \
  --wait --timeout 5m

echo
kubectl -n "$NS" get pods -l app.kubernetes.io/name=fluent-bit -o wide
