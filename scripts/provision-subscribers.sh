#!/bin/bash
#
# provision-subscribers.sh - Sync Open5GS subscriber DB from subscribers.csv
#
# Wipes all existing subscribers and re-inserts from the CSV.
# Run this on the gNB compute node any time subscribers.csv changes.
#
# Usage: sudo /local/repository/scripts/provision-subscribers.sh
#

set -euo pipefail

REPO_DIR="/local/repository"
CSV="${REPO_DIR}/config/subscribers.csv"
MONGO_CMD=$(command -v mongosh || command -v mongo)

echo "======================================"
echo "  Open5GS Subscriber Provisioning"
echo "======================================"
echo "Source: ${CSV}"
echo ""

if [ ! -f "${CSV}" ]; then
    echo "ERROR: subscribers.csv not found at ${CSV}"
    exit 1
fi

# Count non-comment, non-empty lines
TOTAL=$(grep -v '^\s*#' "${CSV}" | grep -v '^\s*$' | wc -l)
if [ "${TOTAL}" -eq 0 ]; then
    echo "ERROR: No subscribers found in ${CSV} (file is empty or all comments)"
    exit 1
fi

echo "Found ${TOTAL} subscriber(s) to provision."
echo ""

# Wipe existing subscribers
echo "Clearing existing subscribers from MongoDB..."
${MONGO_CMD} --quiet open5gs --eval "
    var result = db.subscribers.deleteMany({});
    print('  Deleted ' + result.deletedCount + ' existing subscriber(s).');
"

echo ""
echo "Inserting subscribers..."

COUNT=0
while IFS=',' read -r imsi k opc apn sst sd; do
    # Skip comments and blank lines
    [[ "${imsi}" =~ ^\s*# ]] && continue
    [[ -z "${imsi}" ]] && continue

    # Strip whitespace
    imsi=$(echo "${imsi}" | tr -d '[:space:]')
    k=$(echo "${k}"    | tr -d '[:space:]')
    opc=$(echo "${opc}"  | tr -d '[:space:]')
    apn=$(echo "${apn}"  | tr -d '[:space:]')
    sst=$(echo "${sst}"  | tr -d '[:space:]')

    echo "  Adding IMSI: ${imsi}"

    ${MONGO_CMD} --quiet open5gs --eval "
    db.subscribers.insertOne({
        'imsi': '${imsi}',
        'msisdn': [],
        'imeisv': [],
        'mme_host': [],
        'mme_realm': [],
        'purge_flag': [],
        'security': {
            'k': '${k}',
            'amf': '8000',
            'op_type': 2,
            'op_value': '${opc}',
            'op': null
        },
        'ambr': {
            'downlink': { 'value': 1, 'unit': 3 },
            'uplink':   { 'value': 1, 'unit': 3 }
        },
        'slice': [{
            'sst': ${sst},
            'default_indicator': true,
            'session': [{
                'name': '${apn}',
                'type': 3,
                'pcc_rule': [],
                'ambr': {
                    'downlink': { 'value': 1, 'unit': 3 },
                    'uplink':   { 'value': 1, 'unit': 3 }
                },
                'qos': {
                    'index': 9,
                    'arp': {
                        'priority_level': 8,
                        'pre_emption_capability': 1,
                        'pre_emption_vulnerability': 1
                    }
                }
            }]
        }],
        'schema_version': 1,
        '__v': 0
    });
    " || echo "  WARNING: Failed to insert IMSI ${imsi}"

    COUNT=$((COUNT + 1))
done < "${CSV}"

echo ""
echo "======================================"
echo "  Done — ${COUNT}/${TOTAL} subscriber(s) provisioned."
echo "======================================"
echo ""

# Show final state
echo "Current subscribers in DB:"
${MONGO_CMD} --quiet open5gs --eval "
    db.subscribers.find({}, { imsi: 1, _id: 0 }).forEach(function(s) {
        print('  ' + s.imsi);
    });
"
