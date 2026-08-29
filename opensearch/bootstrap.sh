#!/bin/sh
set -eu

OS="https://opensearch:9200"
AUTH="admin:${ADMIN_PASSWORD}"
ALIAS=logs-k8s
FIRST="${ALIAS}-000001"

req() {
  curl -sk -u "$AUTH" -w '\n%{http_code}' "$@"
}

code_of() { echo "$1" | tail -1; }
body_of() { echo "$1" | sed '$d'; }

echo "waiting for opensearch"
until [ "$(curl -sk -o /dev/null -w '%{http_code}' -u "$AUTH" "$OS/_cluster/health")" = "200" ]; do
  sleep 3
done

echo
echo "1. index template"
R=$(req -X PUT "$OS/_index_template/${ALIAS}" -H 'content-type: application/json' \
      --data-binary @/config/index-template.json)
echo "   HTTP $(code_of "$R")  $(body_of "$R")"

echo
echo "2. lifecycle policy"
EXISTING=$(curl -sk -u "$AUTH" "$OS/_plugins/_ism/policies/${ALIAS}")
SEQ=$(echo "$EXISTING" | sed -n 's/.*"_seq_no":\([0-9]*\).*/\1/p')
PRI=$(echo "$EXISTING" | sed -n 's/.*"_primary_term":\([0-9]*\).*/\1/p')
if [ -n "$SEQ" ] && [ -n "$PRI" ]; then
  echo "   policy exists at seq=$SEQ term=$PRI, updating in place"
  URL="$OS/_plugins/_ism/policies/${ALIAS}?if_seq_no=${SEQ}&if_primary_term=${PRI}"
else
  echo "   policy does not exist, creating"
  URL="$OS/_plugins/_ism/policies/${ALIAS}"
fi
R=$(req -X PUT "$URL" -H 'content-type: application/json' --data-binary @/config/ism-policy.json)
echo "   HTTP $(code_of "$R")"

echo
echo "3. bootstrap index and write alias"
if [ "$(curl -sk -o /dev/null -w '%{http_code}' -u "$AUTH" "$OS/_alias/${ALIAS}")" = "200" ]; then
  echo "   alias ${ALIAS} already exists, leaving it alone"
else
  R=$(req -X PUT "$OS/${FIRST}" -H 'content-type: application/json' \
        -d "{\"aliases\":{\"${ALIAS}\":{\"is_write_index\":true}}}")
  echo "   HTTP $(code_of "$R")  $(body_of "$R")"
fi

echo
echo "4. single-node cluster settings"
R=$(req -X PUT "$OS/_cluster/settings" -H 'content-type: application/json' \
      -d '{"persistent":{"plugins.index_state_management.history.number_of_replicas":"0"}}')
echo "   ISM history replicas -> HTTP $(code_of "$R")"
echo "   (without this the dated ISM history index is born with a replica"
echo "    that a single node can never place, and the cluster goes yellow every day)"

echo
echo "done"
