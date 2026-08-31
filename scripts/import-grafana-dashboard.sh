#!/usr/bin/env bash
# Publish the dashboard as a ConfigMap the Grafana chart mounts, then restart it.
#
# This used to POST to /api/dashboards/db. That writes into Grafana's database, and
# with persistence disabled the database dies with the pod: the dashboard disappeared
# on the next upgrade while the datasources and the alert — provisioned from files —
# came back fine. Everything the lab claims is "as code" now actually is.
set -euo pipefail

NS="${NS:-observability}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$HERE/grafana/make-dashboard.py"
echo

kubectl -n "$NS" create configmap vantia-dashboards \
  --from-file=vantia-request.json="$HERE/grafana/vantia-request.json" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "  configmap vantia-dashboards updated"

kubectl -n "$NS" rollout restart deploy/grafana >/dev/null
kubectl -n "$NS" rollout status deploy/grafana --timeout=300s >/dev/null
echo "  grafana restarted"

NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo
echo "  http://${NODE}:${PORT}/d/vantia-request"
