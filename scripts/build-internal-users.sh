#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-observability}"
POD=opensearch-master-0
SECRET=opensearch-internal-users

read_pass() {
  kubectl -n "$NS" get secret "$1" -o jsonpath='{.data.password}' | base64 -d
}

bcrypt() {
  kubectl -n "$NS" exec -i "$POD" -c opensearch -- sh -c \
    'read -r PW; export PW; cd /usr/share/opensearch && ./plugins/opensearch-security/tools/hash.sh -env PW 2>/dev/null | tail -1'
}

echo "hashing admin"
ADMIN_HASH=$(read_pass opensearch-admin | bcrypt)
echo "hashing kibanaserver"
KIBANA_HASH=$(read_pass opensearch-dashboards | bcrypt)
echo "hashing fluentbit"
FLUENT_HASH=$(read_pass opensearch-fluentbit | bcrypt)
echo "hashing grafana"
GRAFANA_HASH=$(read_pass opensearch-grafana | bcrypt)

for h in "$ADMIN_HASH" "$KIBANA_HASH" "$FLUENT_HASH" "$GRAFANA_HASH"; do
  case "$h" in
    \$2y\$*) ;;
    *) echo "unexpected hash format, refusing to continue: ${h:0:8}..." >&2; exit 1 ;;
  esac
done

FILE=$(mktemp)
trap 'rm -f "$FILE"' EXIT
cat > "$FILE" <<EOF
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "${ADMIN_HASH}"
  reserved: true
  backend_roles:
    - "admin"
  description: "Lab administrator. Password lives in the opensearch-admin secret."

kibanaserver:
  hash: "${KIBANA_HASH}"
  reserved: true
  description: "Service account OpenSearch Dashboards connects with. Password lives in the opensearch-dashboards secret."

fluentbit:
  hash: "${FLUENT_HASH}"
  reserved: false
  opendistro_security_roles:
    - "lab_log_writer"
  description: "Service account Fluent Bit ships logs with. Can only write to logs-k8s*. Password lives in the opensearch-fluentbit secret."

grafana:
  hash: "${GRAFANA_HASH}"
  reserved: false
  opendistro_security_roles:
    - "lab_log_reader"
  description: "Service account Grafana queries logs with. Read-only over logs-k8s*. Password lives in the opensearch-grafana secret."
EOF

kubectl -n "$NS" create secret generic "$SECRET" \
  --from-file=internal_users.yml="$FILE" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo
echo "secret $NS/$SECRET written with 4 users: admin, kibanaserver, fluentbit, grafana"
echo "the demo accounts (logstash, kibanaro, readall, snapshotrestore, anomalyadmin) are dropped"
