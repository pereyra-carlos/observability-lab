#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
POD=opensearch-master-0
OS_HOME=/usr/share/opensearch
SECDIR="$OS_HOME/config/opensearch-security"

ADMIN=$(kubectl -n "$NS" get secret opensearch-admin -o jsonpath='{.data.password}' | base64 -d)

# The chart mounts internal_users.yml with subPath, and subPath mounts never pick up
# changes to the underlying Secret. Without this check securityadmin would happily
# apply a stale file and report success.
WANT=$(kubectl -n "$NS" get secret opensearch-internal-users \
        -o jsonpath='{.data.internal_users\.yml}' | base64 -d | sha256sum | cut -c1-16)
HAVE=$(kubectl -n "$NS" exec "$POD" -c opensearch -- \
        sha256sum "$SECDIR/internal_users.yml" 2>/dev/null | cut -c1-16)

if [ "$WANT" != "$HAVE" ]; then
  echo "mounted file is stale (secret $WANT vs pod $HAVE), restarting opensearch to remount"
  kubectl -n "$NS" rollout restart statefulset/opensearch-master
  kubectl -n "$NS" rollout status statefulset/opensearch-master --timeout=600s
  until kubectl -n "$NS" exec "$POD" -c opensearch -- \
        curl -sk -o /dev/null -u "admin:$ADMIN" "https://localhost:9200/_cluster/health" 2>/dev/null; do
    sleep 5
  done
  echo "remounted"
  echo
fi

echo "role lab_log_writer: append-only access to the log indices and nothing else"
kubectl -n "$NS" exec "$POD" -c opensearch -- curl -sk -u "admin:$ADMIN" \
  -X PUT 'https://localhost:9200/_plugins/_security/api/roles/lab_log_writer' \
  -H 'content-type: application/json' -d '{
    "description": "Ship logs into logs-k8s and nothing else",
    "cluster_permissions": ["cluster_composite_ops", "cluster_monitor"],
    "index_permissions": [
      {
        "index_patterns": ["logs-k8s*"],
        "allowed_actions": ["write", "create_index", "indices:admin/mapping/put"]
      }
    ]
  }' | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ", d.get("status"), "-", d.get("message"))'

echo
echo "role lab_log_reader: read the log indices and nothing else"
kubectl -n "$NS" exec "$POD" -c opensearch -- curl -sk -u "admin:$ADMIN" \
  -X PUT 'https://localhost:9200/_plugins/_security/api/roles/lab_log_reader' \
  -H 'content-type: application/json' -d '{
    "description": "Query logs-k8s and nothing else",
    "cluster_permissions": ["cluster_composite_ops_ro", "cluster_monitor", "cluster:admin/opensearch/ppl"],
    "index_permissions": [
      {
        "index_patterns": ["logs-k8s*"],
        "allowed_actions": ["read", "search", "indices_monitor", "indices:admin/mappings/get", "indices:admin/mappings/fields/get*", "indices:admin/get", "indices:admin/resolve/index", "indices:admin/aliases/get"]
      }
    ]
  }' | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ", d.get("status"), "-", d.get("message"))'

echo
echo "applying $SECDIR/internal_users.yml to the security index"

kubectl -n "$NS" exec "$POD" -c opensearch -- sh -c "
cd $OS_HOME && ./plugins/opensearch-security/tools/securityadmin.sh \
  -f $SECDIR/internal_users.yml -t internalusers \
  -icl -nhnv \
  -cacert config/root-ca.pem -cert config/kirk.pem -key config/kirk-key.pem \
  -h localhost -p 9200" 2>&1 | grep -E "SUCC|ERR|FAIL|Done with"

echo
echo "dropping the cloned role left over from the failed experiment"
kubectl -n "$NS" exec "$POD" -c opensearch -- curl -sk -u "admin:$ADMIN" \
  -X DELETE 'https://localhost:9200/_plugins/_security/api/roles/lab_dashboards_server' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ", d.get("status"), "-", d.get("message"))' || true
