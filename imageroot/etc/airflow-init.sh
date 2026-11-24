#!/bin/bash
set -euo pipefail
airflow db migrate
users=$(airflow users list --output json)
count=$(python -c 'import json,sys; print(sum(user["username"] == "admin" for user in json.load(sys.stdin)))' <<< "$users")
if [[ "$count" == 0 ]]; then
    airflow users create --username admin --firstname NS8 --lastname Administrator \
        --role Admin --email admin@example.org --password "$NS8_ADMIN_PASSWORD"
fi
