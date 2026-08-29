#!/usr/bin/env bash
set -euo pipefail
NS="${NS:-observability}"
HERE="$(dirname "$0")"

PASS=$(kubectl -n "$NS" get secret opensearch-admin -o jsonpath='{.data.password}' | base64 -d)
GP=$(kubectl -n "$NS" get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')

read -r COST N < <(kubectl -n "$NS" exec opensearch-master-0 -c opensearch -- curl -sk -u "admin:$PASS" \
  'https://localhost:9200/logs-k8s/_search' -H 'content-type: application/json' \
  -d '{"size":0,"query":{"bool":{"must":[{"term":{"stage":"generate"}},{"range":{"@timestamp":{"gte":"now-10m"}}}]}},"aggs":{"c":{"sum":{"field":"cost_usd"}},"n":{"value_count":{"field":"cost_usd"}}}}' 2>/dev/null \
  | python3 "$HERE/cost_now.py")

STATE=$(curl -s --max-time 20 -u "admin:$GP" "http://${NODE}:${PORT}/api/prometheus/grafana/api/v1/rules" 2>/dev/null \
  | python3 "$HERE/rule_state.py" || echo "?")

printf "  costo 10min = \$%s   requests = %s   umbral = 0.60   regla = %s\n" "$COST" "$N" "${STATE:-?}"
