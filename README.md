# Apache Airflow for NS8

NS8 module that runs [Apache Airflow](https://airflow.apache.org/) 3.4.0, a
platform to author, schedule and monitor workflows defined as Python DAGs. The
web interface is published through the NS8 Traefik reverse proxy.

## Architecture

Every instance is a rootless Podman pod with five containers:

| Container | Purpose |
|---|---|
| `airflow-db` | PostgreSQL 17, the Airflow metadata database |
| `airflow-web` | Airflow API server and web interface (listens on loopback only) |
| `airflow-scheduler` | DAG scheduler and task executor (`LocalExecutor`) |
| `airflow-dag-processor` | parses the DAG files |
| `airflow-triggerer` | runs deferrable operators |

Start order: pod, database, web (migrates the database and creates the initial
admin user), then scheduler, dag-processor and triggerer. This is a
single-node deployment. DAG code runs inside the module, so install DAGs only
from trusted authors.

## Install

Install the module from the NS8 Software Center, or from the command line of the
leader node:

```sh
add-module ghcr.io/geniusdynamics/airflow:latest 1
```

The command prints the new module ID, for example `airflow1`.

## Configuration

Open the module page and go to Settings, or run:

```sh
api-cli run module/airflow1/configure-module --data '{"host":"airflow.example.org","lets_encrypt":false,"http2https":true}'
```

| Field | Description |
|---|---|
| `host` | Required. Fully qualified hostname, it must resolve to the node. |
| `lets_encrypt` | Request a Let's Encrypt certificate (default: false). |
| `http2https` | Redirect HTTP to HTTPS (default: true). |

Read the current settings with `api-cli run module/airflow1/get-configuration`.
No secret is ever returned by this action.

The public URL (`https://<host>`) and proxy headers are configured for Airflow
automatically.

## Credentials

Passwords and keys are generated once, when the module is created, and stored
in files readable only by the module under its `state` directory:

| File | Content | Used by |
|---|---|---|
| `database.env` | PostgreSQL user and password | database container |
| `airflow.env` | Fernet key, JWT and API secret keys, database connection string | Airflow containers |
| `admin.env` | initial administrator password | first-start init step |

They never appear in command lines, logs or action output.

The initial administrator is the user `admin`. Read the generated password on
the node, as root:

```sh
runagent -m airflow1 airflow-initial-credentials
```

Change it from the Airflow web interface after the first login. The file is
only read when the `admin` user does not exist yet, so a changed password is
never overwritten, and the printed password is no longer valid once changed.

## Backup and restore

Configure a backup for the instance in the NS8 Backup page. A backup contains:

- a consistent PostgreSQL dump (`pg_dump`, taken while the application keeps
  running);
- the `airflow-data` volume, holding DAGs, plugins and task logs (scheduler and
  DAG processor logs are excluded);
- the secret files listed above, so the same keys and passwords are restored.

On restore, the secrets and `airflow-data` are restored first, the database is
loaded from the dump into a new volume, and the module is configured again.
Let's Encrypt is not restored, because DNS may not point to the new node yet:
enable it again from Settings when ready.

Back up the Fernet key together with the database: without it the encrypted
connections and variables stored in the database cannot be read.

## Upgrade

Updates are delivered through the NS8 Software Center (or `update-module`). The
update restarts the services, and the web service migrates the database
schema at start. Take a backup before upgrading to a new Airflow minor version.

## Troubleshooting

Run these commands on the node as root, replacing `airflow1` with the module ID.

```sh
runagent -m airflow1 systemctl --user status airflow.service airflow-db airflow-web airflow-scheduler airflow-dag-processor airflow-triggerer
runagent -m airflow1 journalctl --user -u airflow-web -n 100
runagent -m airflow1 podman ps
```

- The web page does not load: check that `airflow-db` is active first, since
  every other service depends on it, then `airflow-web`.
- Login fails: print the initial password as shown above. If the password was
  changed in the web interface, reset it with
  `runagent -m airflow1 podman exec -it airflow-web airflow users reset-password -u admin`.
- Settings reports "domain already used": another module already publishes
  that hostname in Traefik.
- DAGs are not listed: copy files into the `airflow-data` volume under `dags/`
  (`runagent -m airflow1 podman volume inspect airflow-data` shows its path) and
  check `airflow-dag-processor` logs for import errors.

## Development

- Build the images with `./build-images.sh`.
- The UI is in `ui/` (Vue 2, Carbon, `ns8-ui-lib`). Only
  `ui/public/i18n/en/translation.json` is edited by hand, other languages
  come from Weblate.
- Integration tests are in `tests/` (Robot Framework) and run on a QEMU NS8
  node by the `Test module on QEMU` workflow, or with
  `./test-module.sh <node> ghcr.io/geniusdynamics/airflow:<tag>`.
