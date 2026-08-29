#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$HERE/opensearch/make-dashboard.py"
echo

NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc opensearch-dashboards -o jsonpath='{.spec.ports[0].nodePort}')
URL="http://${NODE}:${PORT}"
PASS=$(kubectl -n "$NS" get secret opensearch-admin -o jsonpath='{.data.password}' | base64 -d)

JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

curl -sS -c "$JAR" -o /dev/null -X POST "$URL/auth/login" \
  -H 'content-type: application/json' -H 'osd-xsrf: true' \
  -d "{\"username\":\"admin\",\"password\":\"$PASS\"}"

curl -sS -b "$JAR" -X POST "$URL/api/saved_objects/_import?overwrite=true" \
  -H 'osd-xsrf: true' \
  -F file=@"$HERE/opensearch/vantia-dashboard.ndjson" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("  success:", d.get("success"), "· objects:", d.get("successCount"))
for e in d.get("errors", []):
    print("  ERROR", e.get("type"), e.get("id"), e.get("error"))'

# An imported index-pattern has no field list, and visualizations that aggregate
# fail with "Trying to initialize aggs without index pattern" until it has one.
# The UI fills it in when you create the pattern by hand; on import nothing does.
echo
echo "refreshing the index pattern field list"

FIELDS=$(curl -sS -b "$JAR" \
  "$URL/api/index_patterns/_fields_for_wildcard?pattern=logs-k8s*&meta_fields=_source&meta_fields=_id&meta_fields=_type&meta_fields=_index&meta_fields=_score" \
  | python3 -c 'import sys,json; print(json.dumps(json.dumps(json.load(sys.stdin)["fields"])))')

curl -sS -b "$JAR" -X PUT "$URL/api/saved_objects/index-pattern/logs-k8s" \
  -H 'osd-xsrf: true' -H 'content-type: application/json' \
  -d "{\"attributes\":{\"title\":\"logs-k8s*\",\"timeFieldName\":\"@timestamp\",\"fields\":${FIELDS}}}" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
n = len(json.loads(d["attributes"]["fields"]))
print(f"  index pattern now knows {n} fields")'

echo
echo "  $URL/app/dashboards#/view/vantia-assistant"
