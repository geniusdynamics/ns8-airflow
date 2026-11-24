*** Settings ***
Library    SSHLibrary

*** Variables ***
${TEST_HOST}    airflow.ns8-ci.test

*** Test Cases ***
Install airflow
    ${output}    ${rc}=    Execute Command    timeout 300 add-module ${IMAGE_URL} 1    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${result}=    Evaluate    ast.literal_eval($output)    modules=ast
    Set Suite Variable    ${module_id}    ${result}[module_id]

Reject invalid hostname
    ${rc}=    Execute Command    timeout 120 api-cli run module/${module_id}/configure-module --data '{"host":"nodots"}'    return_stdout=False    return_rc=True
    Should Not Be Equal As Integers    ${rc}    0

Configure airflow
    ${rc}=    Execute Command    timeout 600 api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","lets_encrypt":false,"http2https":true}'    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Get configuration returns settings and no secrets
    ${output}    ${rc}=    Execute Command    api-cli run module/${module_id}/get-configuration    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${output}    ${TEST_HOST}
    Should Not Contain    ${output.lower()}    password
    Should Not Contain    ${output.lower()}    secret
    Should Not Contain    ${output.lower()}    fernet

Secret files are private
    ${out}    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'for f in airflow.env database.env admin.env; do stat -c "%a" "$f"; done'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Be Equal    ${out}    600\n600\n600

Check Web Response
    Check Health

Admin can log in with the initial password
    Check Admin Login

Check Airflow Background Services
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'for unit in db web scheduler dag-processor triggerer; do systemctl --user is-active --quiet "airflow-$unit.service"; done'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Backup dump is consistent and cleaned up
    ${rc}=    Execute Command    timeout 330 runagent -m ${module_id} module-dump-state    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'test -s airflow.pg_dump && podman exec -i airflow-db pg_restore --list < airflow.pg_dump | grep -q dag'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${rc}=    Execute Command    runagent -m ${module_id} module-cleanup-state    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${rc}=    Execute Command    runagent -m ${module_id} test ! -e airflow.pg_dump    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Restore database from dump
    ${rc}=    Execute Command    timeout 330 runagent -m ${module_id} module-dump-state    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${rc}=    Execute Command
    ...    timeout 600 runagent -m ${module_id} bash -ec 'systemctl --user stop airflow.service && podman volume rm airflow-db && "$AGENT_INSTALL_DIR/actions/restore-module/40restore-postgres" && systemctl --user start airflow.service airflow-db.service airflow-web.service airflow-scheduler.service airflow-dag-processor.service airflow-triggerer.service'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Check Health
    Check Admin Login

Remove airflow
    ${rc}=    Execute Command    remove-module --no-preserve ${module_id}    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

*** Keywords ***
Check Health
    ${rc}=    Execute Command    curl -kfsS --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/api/v2/version >/dev/null    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Check Admin Login
    ${code}    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'pw=$(sed -n "s/^NS8_ADMIN_PASSWORD=//p" admin.env); curl -ksS -o /dev/null -w "\%{http_code}" --resolve ${TEST_HOST}:443:127.0.0.1 -H "Content-Type: application/json" -d "{\\"username\\":\\"admin\\",\\"password\\":\\"$pw\\"}" https://${TEST_HOST}/auth/token'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Match Regexp    ${code}    ^(200|201)$
