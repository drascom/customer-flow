#!/usr/bin/env bash
set -euo pipefail

readonly repo="/home/ubuntu/customer-flow-demo"
readonly branch="main"
readonly service_name="customer-flow-demo.service"
readonly health_url="http://127.0.0.1:8080/api/v1/health"
readonly lock_path="/run/lock/customer-flow-demo-maintenance.lock"

exec 9>"${lock_path}"
flock -w 120 9

as_deploy_user() {
    runuser -u ubuntu -- "$@"
}

if [[ -n "$(as_deploy_user git -C "${repo}" status --porcelain --untracked-files=no)" ]]; then
    logger -t customer-flow-demo-deploy "Deploy skipped: tracked files are modified."
    exit 1
fi

as_deploy_user git -C "${repo}" fetch --quiet origin "${branch}"
previous_revision="$(as_deploy_user git -C "${repo}" rev-parse HEAD)"
target_revision="$(as_deploy_user git -C "${repo}" rev-parse "origin/${branch}")"

if [[ "${previous_revision}" == "${target_revision}" ]]; then
    exit 0
fi

if ! as_deploy_user git -C "${repo}" merge-base --is-ancestor \
    "${previous_revision}" "${target_revision}"; then
    logger -t customer-flow-demo-deploy "Deploy refused: origin/${branch} is not a fast-forward."
    exit 1
fi

as_deploy_user git -C "${repo}" merge --quiet --ff-only "${target_revision}"
systemctl restart "${service_name}"

for _ in {1..30}; do
    if curl --fail --silent --show-error "${health_url}" >/dev/null; then
        logger -t customer-flow-demo-deploy \
            "Deployed ${target_revision} and restarted ${service_name}."
        exit 0
    fi
    sleep 1
done

logger -t customer-flow-demo-deploy \
    "Health check failed for ${target_revision}; rolling back to ${previous_revision}."
as_deploy_user git -C "${repo}" reset --hard "${previous_revision}"
systemctl restart "${service_name}"

for _ in {1..30}; do
    if curl --fail --silent --show-error "${health_url}" >/dev/null; then
        exit 1
    fi
    sleep 1
done

echo "Customer Flow demo remained unhealthy after rollback." >&2
exit 1
