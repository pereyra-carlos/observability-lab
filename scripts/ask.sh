#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

TENANT="${1:-acme}"
SCENARIO="${2:-normal}"
QUESTION="${3:-why was my invoice charged twice}"

URL=$(gateway_url)
if [ "$URL" = "NO_NODEPORT" ]; then
  echo "no NodePort on vantia-gateway. Run this in another terminal:" >&2
  echo "  kubectl -n $NS port-forward svc/vantia-gateway 8080:8080" >&2
  echo "then re-run with GATEWAY_URL=http://localhost:8080" >&2
  exit 1
fi

curl -sS --max-time 10 -X POST "$URL/ask" \
  -H 'content-type: application/json' \
  -d "{\"tenant\":\"$TENANT\",\"question\":\"$QUESTION\",\"scenario\":\"$SCENARIO\"}"
echo
