#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$HERE/grafana/make-dashboard.py"
echo

NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
PORT=$(kubectl -n "$NS" get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')
PASS=$(kubectl -n "$NS" get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d)
URL="http://${NODE}:${PORT}"

python3 -c "
import json,sys
d=json.load(open('$HERE/grafana/vantia-request.json'))
print(json.dumps({'dashboard': d, 'overwrite': True, 'folderId': 0}))" > /tmp/vantia-dash.json

curl -sS -u "admin:$PASS" -X POST "$URL/api/dashboards/db" \
  -H 'content-type: application/json' --data-binary @/tmp/vantia-dash.json \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("  status:", d.get("status", "ok"), "· version:", d.get("version"))
if d.get("message") and d.get("status") != "success": print("  ", d["message"])'
rm -f /tmp/vantia-dash.json

echo
echo "  $URL/d/vantia-request"
