#!/usr/bin/env bash
set -euo pipefail

readonly service_name="customer-flow-demo.service"
readonly data_root="/var/lib/customer-flow-demo"
readonly database_name="customer-flow.sqlite3"
readonly database_path="${data_root}/${database_name}"
readonly media_root="${data_root}/media"
readonly lock_path="/run/lock/customer-flow-demo-maintenance.lock"

exec 9>"${lock_path}"
flock -w 120 9

if [[ "${data_root}" != "/var/lib/customer-flow-demo" ]]; then
    echo "Refusing to reset an unexpected data directory." >&2
    exit 1
fi

systemctl stop "${service_name}"
trap 'systemctl start "${service_name}" >/dev/null 2>&1 || true' EXIT

install -d -o ubuntu -g ubuntu -m 700 "${data_root}" "${media_root}"
find "${data_root}" -maxdepth 1 -type f \
    \( -name "${database_name}" -o -name "${database_name}-shm" -o -name "${database_name}-wal" \) \
    -delete
find "${media_root}" -mindepth 1 -delete

systemctl start "${service_name}"
trap - EXIT

for _ in {1..20}; do
    if curl --fail --silent --show-error \
        http://127.0.0.1:8080/api/v1/health >/dev/null; then
        logger -t customer-flow-demo-reset "Demo database and media reset completed."
        exit 0
    fi
    sleep 1
done

echo "Customer Flow demo did not become healthy after reset." >&2
exit 1
