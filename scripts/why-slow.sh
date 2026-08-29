#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
HERE="$(dirname "$0")"
RID="${1:-}"

os() {
  local pass
  pass=$(kubectl -n "$NS" get secret opensearch-admin -o jsonpath='{.data.password}' | base64 -d)
  kubectl -n "$NS" exec opensearch-master-0 -c opensearch -- \
    curl -sk -u "admin:$pass" "$@" 2>/dev/null
}

if [ -z "$RID" ]; then
  echo "no request given, taking the slowest one of the last two hours"
  RID=$(os 'https://localhost:9200/logs-k8s/_search' -H 'content-type: application/json' -d '{
      "size":1,"sort":[{"total_ms":"desc"}],
      "query":{"bool":{"must":[{"term":{"stage":"generate"}},{"exists":{"field":"trace_id"}},
                               {"range":{"@timestamp":{"gte":"now-2h"}}}]}},
      "_source":["request_id"]}' \
    | python3 -c 'import sys,json; h=json.load(sys.stdin)["hits"]["hits"]; print(h[0]["_source"]["request_id"] if h else "")')
fi

[ -z "$RID" ] && { echo "nothing to look at" >&2; exit 1; }

echo
echo "=============== THE LOGS ==============="
os "https://localhost:9200/logs-k8s/_search?q=request_id:${RID}&sort=ts:asc&size=20" \
  | python3 "$HERE/format_hits.py"

TID=$(os "https://localhost:9200/logs-k8s/_search?q=request_id:${RID}&size=1" \
  | python3 -c 'import sys,json; h=json.load(sys.stdin)["hits"]["hits"]; print((h[0]["_source"].get("trace_id") or "") if h else "")')

if [ -z "$TID" ]; then
  echo "  these logs carry no trace_id: written before the app was instrumented."
  exit 0
fi

echo "=============== THE TRACE =============="
echo "  the logs above carry trace_id=$TID"
echo "  that field is the whole link. Same request, drawn instead of listed:"
echo
kubectl -n "$NS" exec tempo-0 -- wget -qO- "http://localhost:3200/api/traces/${TID}" 2>/dev/null \
  | python3 "$HERE/format_trace.py"

NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')
echo "  in Grafana:"
echo "    http://${NODE}:${PORT}/explore?left=%7B%22datasource%22:%22tempo-traces%22,%22queries%22:%5B%7B%22query%22:%22${TID}%22,%22queryType%22:%22traceId%22%7D%5D%7D"
