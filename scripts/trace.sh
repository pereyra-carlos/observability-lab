#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

RID="${1:-}"
if [ -z "$RID" ]; then
  echo "usage: trace.sh <request_id>" >&2
  exit 1
fi

echo "looking for $RID in every running pod of the assistant"
echo

TOTAL=0
while read -r pod; do
  LINES=$(kubectl -n "$NS" logs "$pod" --tail=1000 2>/dev/null | grep -F -- "$RID" || true)
  COUNT=$(printf '%s' "$LINES" | grep -c . || true)
  TOTAL=$((TOTAL + COUNT))
  if [ "$COUNT" -gt 0 ]; then
    printf '  \033[32mfound\033[0m  %s\n' "${pod#pod/}"
    printf '%s\n' "$LINES" | sed 's/^/         /'
  else
    printf '  ----   %s\n' "${pod#pod/}"
  fi
done < <(app_pods)

echo
echo "lines found: $TOTAL"
