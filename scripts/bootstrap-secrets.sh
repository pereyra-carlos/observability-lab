#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"

make_secret() {
  local name="$1" user="$2"
  if kubectl -n "$NS" get secret "$name" >/dev/null 2>&1; then
    echo "secret $NS/$name already exists, leaving it alone"
    return
  fi
  kubectl -n "$NS" create secret generic "$name" \
    --from-literal=username="$user" \
    --from-literal=password="$(openssl rand -hex 12)Aa1!" >/dev/null
  echo "created secret $NS/$name"
}

make_secret opensearch-admin      admin
make_secret opensearch-dashboards kibanaserver
make_secret opensearch-fluentbit  fluentbit
make_secret opensearch-grafana    grafana
make_secret grafana-admin         admin

echo
echo "read any of them back with:"
echo "  kubectl -n $NS get secret <name> -o jsonpath='{.data.password}' | base64 -d; echo"

# Where the cost alert goes. Anything that speaks HTTP works: Slack, a script,
# an agent that writes you a sentence. Override with:
#   ALERT_WEBHOOK_URL=https://... ./scripts/bootstrap-secrets.sh
if ! kubectl -n "$NS" get secret alert-webhook >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic alert-webhook \
    --from-literal=url="${ALERT_WEBHOOK_URL:-http://example.invalid/alerts}" >/dev/null
  echo "created secret $NS/alert-webhook"
  [ -z "${ALERT_WEBHOOK_URL:-}" ] && \
    echo "  no ALERT_WEBHOOK_URL set — it points nowhere. The alert will fire and go unheard."
fi
