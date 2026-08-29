#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

kubectl -n "$NS" create configmap opensearch-bootstrap \
  --from-file="$HERE/opensearch/index-template.json" \
  --from-file="$HERE/opensearch/ism-policy.json" \
  --from-file="$HERE/opensearch/bootstrap.sh" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$NS" delete job opensearch-bootstrap --ignore-not-found >/dev/null
kubectl -n "$NS" apply -f "$HERE/deploy/20-opensearch-bootstrap-job.yaml" >/dev/null
kubectl -n "$NS" wait --for=condition=complete job/opensearch-bootstrap --timeout=180s >/dev/null

echo
kubectl -n "$NS" logs job/opensearch-bootstrap

echo
echo "single-node hygiene: replicas the cluster can never place"
echo "  these are protected system indices: even admin gets 403 over REST,"
echo "  so this runs inside the pod with the admin certificate"
for IDX in .opendistro-ism-config .opensearch-observability .ql-datasources .kibana_1 ".opendistro-ism-managed-index-history-*"; do
  kubectl -n "$NS" exec opensearch-master-0 -c opensearch -- sh -c "
    if curl -sk -o /dev/null -w '%{http_code}' --cert config/kirk.pem --key config/kirk-key.pem \
         --cacert config/root-ca.pem https://localhost:9200/$IDX | grep -q 200; then
      R=\$(curl -sk -o /dev/null -w '%{http_code}' --cert config/kirk.pem --key config/kirk-key.pem \
           --cacert config/root-ca.pem -X PUT 'https://localhost:9200/$IDX/_settings' \
           -H 'content-type: application/json' -d '{\"index\":{\"number_of_replicas\":0}}')
      echo '  $IDX -> HTTP '\$R
    fi" 2>/dev/null
done
