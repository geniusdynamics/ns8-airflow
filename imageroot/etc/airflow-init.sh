#!/bin/bash
#
# Runs inside an ephemeral Airflow container before the API server starts:
# migrates the metadata database and creates the initial "admin" user if it
# does not exist. The password comes from the environment (admin.env), never
# from the command line, and an existing admin user is never modified.
#
set -euo pipefail
airflow db migrate
python - <<'PY'
import os
from airflow.providers.fab.auth_manager.cli_commands.utils import get_application_builder

with get_application_builder() as appbuilder:
    sm = appbuilder.sm
    if sm.find_user("admin"):
        print("admin user already exists")
    else:
        user = sm.add_user("admin", "NS8", "Administrator", "admin@localhost",
                           sm.find_role("Admin"), os.environ["NS8_ADMIN_PASSWORD"])
        if not user:
            raise SystemExit("cannot create the admin user")
        print("admin user created")
PY
