# Customer Flow API

The API contains the versioned HTTP endpoints, authentication, SQLite database layer and uploaded-media storage used by Customer Flow clients. It can also serve the separate [`../admin-panel/`](../admin-panel/) interface.

## Requirements

- A Linux server with `systemd` for the automatic service installation
- Root or `sudo` access
- Python 3.9 or newer
- No third-party Python packages are required

The included `install.sh` is intended for Linux machines. It does not install a system service on macOS or Windows.

## Automatic Linux installation

```bash
cd api
chmod +x install.sh
sudo ./install.sh
```

The installer:

- copies the API and admin panel to `/opt/customer-flow`;
- creates an unprivileged `customer-flow` system user;
- stores the SQLite database and patient media under `/var/lib/customer-flow`;
- creates `/etc/customer-flow/customer-flow.env` with secure initial passwords;
- registers and starts `customer-flow-api.service`;
- enables the service so it starts automatically after every reboot;
- preserves the existing database, media and configuration when run again for an update.

The initial administrator username and generated password are shown once at the end of the first installation. Save them securely and change the password after signing in.

Open after installation:

- Health check: `http://SERVER_IP:8080/api/v1/health`
- Admin panel: `http://SERVER_IP:8080/admin`

### Service management

```bash
sudo systemctl status customer-flow-api
sudo systemctl restart customer-flow-api
sudo journalctl -u customer-flow-api -f
```

Edit `/etc/customer-flow/customer-flow.env` to change the port or configure SMTP, then restart the service.

## Manual development setup

On a development machine, the API can still be started without installing a service:

```bash
cd api
export CF_ADMIN_PASSWORD='change-this-admin-password'
export CF_DOCTOR_PASSWORD='change-this-doctor-password'
export CF_AGENT_PASSWORD='change-this-agent-password'
python3 app.py --host 127.0.0.1 --port 8080
```

The first start creates the SQLite database in `data/customer-flow.sqlite3` and development users only when the database is empty. Accounts for real users should then be created from the admin panel. There is no public registration endpoint.

By default, the API loads the admin panel from the sibling `../admin-panel` folder. Set `CF_ADMIN_DIR` if you deploy that folder somewhere else on the same host.

## Password recovery by email

Set these variables before starting the server:

```bash
export CF_SMTP_HOST='smtp.example.com'
export CF_SMTP_PORT='465'
export CF_SMTP_USERNAME='smtp-user'
export CF_SMTP_PASSWORD='smtp-password'
export CF_SMTP_FROM='Customer Flow <no-reply@example.com>'
```

Implicit TLS is used by default. Set `CF_SMTP_SSL=0` to use STARTTLS.

## Production notes

- Put the service behind an HTTPS reverse proxy.
- Use strong initial passwords and protect all environment variables.
- For automatic installations, back up `/var/lib/customer-flow` securely. For manual development installations, back up the local `data/` and `media/` folders.
- Never commit the SQLite database, uploaded patient media or SMTP credentials.
- Run `sudo ./install.sh` again after pulling a new version to update the installed application safely.

## Tests

```bash
cd api
python3 -m unittest discover -s tests -v
```
