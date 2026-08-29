set -euo pipefail

NS="${NS:-vantia}"

gateway_url() {
  if [ -n "${GATEWAY_URL:-}" ]; then
    echo "$GATEWAY_URL"
    return
  fi
  local ip
  ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  local port
  port=$(kubectl -n "$NS" get svc vantia-gateway -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
  if [ -n "$port" ]; then
    echo "http://${ip}:${port}"
  else
    echo "NO_NODEPORT"
  fi
}

app_pods() {
  kubectl -n "$NS" get pods -o name --field-selector=status.phase=Running \
    | grep -E 'gateway|retrieval|llm-worker'
}
