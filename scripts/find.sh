#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
HERE="$(dirname "$0")"
RID="${1:-}"

if [ -z "$RID" ]; then
  echo "usage: find.sh <request_id>" >&2
  echo "  what trace.sh does, except it asks one place instead of every pod" >&2
  exit 1
fi

PASS=$(kubectl -n "$NS" get secret opensearch-admin -o jsonpath='{.data.password}' | base64 -d)

kubectl -n "$NS" exec opensearch-master-0 -c opensearch -- curl -sk -u "admin:$PASS" \
  "https://localhost:9200/logs-k8s/_search?q=request_id:${RID}&sort=ts:asc&size=20" 2>/dev/null \
  | python3 "$HERE/format_hits.py"
