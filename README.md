# Apache Airflow for NS8

This module runs Apache Airflow 3.4.0 with a dedicated PostgreSQL database behind
NS8 Traefik. Configure a DNS hostname and HTTPS certificate in Settings.
Retrieve the generated first-start password on the instance node.

```sh
runagent -m airflow1 airflow-initial-credentials
```

Sign in as `admin`. Both data volumes and credentials are included in NS8
backup. The backup stops the application and database briefly for consistency.
Restore into empty volumes using the same module version before upgrading.

This is a single-node deployment using Airflow LocalExecutor. The API server,
scheduler, DAG processor and triggerer share the application's persistent volume.
Only install DAGs from trusted authors. DAG code runs inside the module.
