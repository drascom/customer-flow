#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="customer-flow-api.service"
SERVICE_USER="customer-flow"
INSTALL_ROOT="/opt/customer-flow"
STATE_ROOT="/var/lib/customer-flow"
CONFIG_ROOT="/etc/customer-flow"
ENV_FILE="${CONFIG_ROOT}/customer-flow.env"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
ADMIN_SOURCE="${PROJECT_DIR}/admin-panel"

fail() {
  printf 'Customer Flow installation failed: %s\n' "$1" >&2
  exit 1
}

[[ "$(uname -s)" == "Linux" ]] || fail "install.sh requires a Linux machine."
[[ "${EUID}" -eq 0 ]] || fail "run this script as root, for example: sudo ./install.sh"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required."
command -v python3 >/dev/null 2>&1 || fail "Python 3.9 or newer is required."
command -v install >/dev/null 2>&1 || fail "the install command is required."
command -v useradd >/dev/null 2>&1 || fail "the useradd command is required."
python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' \
  || fail "Python 3.9 or newer is required."

[[ -f "${SCRIPT_DIR}/app.py" ]] || fail "api/app.py could not be found."
[[ -f "${SCRIPT_DIR}/deploy/customer-flow-api.service" ]] \
  || fail "the systemd service template could not be found."
[[ -f "${ADMIN_SOURCE}/index.html" ]] || fail "the sibling admin-panel folder could not be found."

if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "${STATE_ROOT}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

install -d -m 0755 "${INSTALL_ROOT}/api" "${INSTALL_ROOT}/admin-panel"
install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 \
  "${STATE_ROOT}" "${STATE_ROOT}/data" "${STATE_ROOT}/media"
install -d -m 0750 "${CONFIG_ROOT}"

install -m 0755 "${SCRIPT_DIR}/app.py" "${INSTALL_ROOT}/api/app.py"
install -m 0644 "${ADMIN_SOURCE}/index.html" "${INSTALL_ROOT}/admin-panel/index.html"
install -m 0644 "${ADMIN_SOURCE}/admin.css" "${INSTALL_ROOT}/admin-panel/admin.css"
install -m 0644 "${ADMIN_SOURCE}/admin.js" "${INSTALL_ROOT}/admin-panel/admin.js"

created_environment=0
if [[ ! -f "${ENV_FILE}" ]]; then
  umask 077
  admin_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
  doctor_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
  agent_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
  {
    printf 'CF_HOST=0.0.0.0\n'
    printf 'CF_PORT=8080\n'
    printf 'CF_DB_PATH=/var/lib/customer-flow/data/customer-flow.sqlite3\n'
    printf 'CF_MEDIA_ROOT=/var/lib/customer-flow/media\n'
    printf 'CF_ADMIN_DIR=/opt/customer-flow/admin-panel\n'
    printf 'CF_ADMIN_PASSWORD=%s\n' "${admin_password}"
    printf 'CF_DOCTOR_PASSWORD=%s\n' "${doctor_password}"
    printf 'CF_AGENT_PASSWORD=%s\n' "${agent_password}"
    printf 'CF_SMTP_HOST=\n'
    printf 'CF_SMTP_PORT=465\n'
    printf 'CF_SMTP_USERNAME=\n'
    printf 'CF_SMTP_PASSWORD=\n'
    printf 'CF_SMTP_FROM=\n'
  } > "${ENV_FILE}"
  created_environment=1
fi
chown root:root "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

install -m 0644 "${SCRIPT_DIR}/deploy/customer-flow-api.service" "${SYSTEMD_FILE}"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
  fail "the service was installed but did not start."
fi

printf '\nCustomer Flow API is installed and running.\n'
printf 'Health: http://SERVER_IP:8080/api/v1/health\n'
printf 'Admin:  http://SERVER_IP:8080/admin\n'
printf 'Service: systemctl status %s\n' "${SERVICE_NAME}"
printf 'Configuration: %s\n' "${ENV_FILE}"

if [[ "${created_environment}" -eq 1 ]]; then
  printf '\nInitial administrator username: admin\n'
  printf 'Initial administrator password: %s\n' "${admin_password}"
  printf 'Save this password securely and change it after the first sign-in.\n'
else
  printf '\nExisting configuration and passwords were preserved.\n'
fi

printf '\nPlace the API behind an HTTPS reverse proxy before production use.\n'
