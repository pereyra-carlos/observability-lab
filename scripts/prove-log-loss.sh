#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

HERE="$(dirname "$0")"

echo "=== 1. one question through the assistant ==="
RID=$("$HERE/ask.sh" "${1:-initech}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["request_id"])')
echo "request_id = $RID"
sleep 8

echo
echo "=== 2. where its lines live right now ==="
BEFORE=$("$HERE/trace.sh" "$RID" | tail -1 | grep -oE '[0-9]+$')
"$HERE/trace.sh" "$RID" | grep -E 'found|----'

echo
echo "=== 3. restarting retrieval, as a deploy would ==="
kubectl -n "$NS" rollout restart deploy/vantia-retrieval >/dev/null
kubectl -n "$NS" rollout status deploy/vantia-retrieval --timeout=120s >/dev/null
kubectl -n "$NS" wait --for=delete pod -l app=vantia-retrieval,pod-template-hash!="$(kubectl -n "$NS" get deploy vantia-retrieval -o jsonpath='{.metadata.labels.pod-template-hash}')" --timeout=60s >/dev/null 2>&1 || sleep 20

echo
echo "=== 4. same search, after the restart ==="
AFTER=$("$HERE/trace.sh" "$RID" | tail -1 | grep -oE '[0-9]+$')
"$HERE/trace.sh" "$RID" | grep -E 'found|----'

echo
echo "lines before the restart: $BEFORE"
echo "lines after  the restart: $AFTER"
echo
if [ "${AFTER:-0}" -lt "${BEFORE:-0}" ]; then
  echo "part of the conversation is gone for good. kubectl logs reads the buffer"
  echo "of a live container, not a history file. This is what phase 1 fixes."
fi
