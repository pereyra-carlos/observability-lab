#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
CHART_VERSION=0.171.0
HERE="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --version "$CHART_VERSION" \
  --namespace "$NS" \
  --values "$HERE/otel/collector-values.yaml" \
  --wait --timeout 8m

echo
kubectl -n "$NS" get pods -l app.kubernetes.io/name=opentelemetry-collector
