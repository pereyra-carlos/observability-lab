#!/usr/bin/env bash
# Make the bill spike on purpose, and put it back.
#
# The alert exists to catch a condition that never happens on its own: the generator
# produces a steady mix, so cost per hour is flat.
#
# Raising only the share of expensive requests is not enough — measured. At 50%
# token_spike the workers saturate, the queue backs up, and fewer requests complete
# per minute. The system's own backpressure caps the spend at about twice normal.
# A real bill spike is pricier requests AND more of them, so this raises the rate and
# adds capacity to serve it.
set -euo pipefail

NS="${NS:-vantia}"

if [ "${1:-on}" = "off" ]; then
  WEIGHTS="88,5,5,2"; RPS="0.3"; WORKERS=3
  echo "back to normal: mix $WEIGHTS, $RPS req/s, $WORKERS workers"
else
  WEIGHTS="20,5,70,5"; RPS="0.8"; WORKERS=6
  echo "spiking: mix $WEIGHTS, $RPS req/s, $WORKERS workers"
fi

kubectl -n "$NS" set env deploy/vantia-loadgen LOADGEN_WEIGHTS="$WEIGHTS" LOADGEN_RPS="$RPS" >/dev/null
kubectl -n "$NS" scale deploy/vantia-llm-worker --replicas="$WORKERS" >/dev/null
kubectl -n "$NS" rollout status deploy/vantia-loadgen --timeout=120s >/dev/null
kubectl -n "$NS" rollout status deploy/vantia-llm-worker --timeout=180s >/dev/null

echo "  done. The rule evaluates every minute and the condition must hold for 5m."
echo "  watch:  watch -n30 './scripts/cost-now.sh'"
