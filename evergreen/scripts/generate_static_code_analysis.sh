#!/bin/bash

set -o errexit

export SEMGREP_APP_TOKEN=${semgrep_app_token}
echo "SEMGREP_APP_TOKEN = ${SEMGREP_APP_TOKEN}"
echo "Running static code analysis with Semgrep..."

# Setup or use the existing virtualenv for semgrep
if [[ -f "venv/bin/activate" ]]; then
    echo 'using existing virtualenv'
    . venv/bin/activate
else
    echo 'Creating new virtualenv'
    python3 -m virtualenv venv
    echo 'Activating new virtualenv'
    . venv/bin/activate
fi
python3 -m pip install semgrep
# Confirm semgrep version
semgrep --version
set +e
semgrep --config p/rust --sarif --exclude "integration_test" --verbose --error --severity=ERROR --sarif-output=${STATIC_CODE_ANALYSIS_NAME} > ${STATIC_CODE_ANALYSIS_NAME}.cmd.verbose.out 2>&1
SCAN_RESULT=$?
set -e
# Exit with a failure if the scan found an issue
exit $SCAN_RESULT