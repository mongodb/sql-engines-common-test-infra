#!/bin/bash

set -o errexit

echo ">>>> Scan SBOM for vulnerabilities..."
if [[ "$ALLOW_VULNS" != "" ]]; then
  echo "Vulnerability ids to ignore : $ALLOW_VULNS"

  echo "-- Generate .grype.yaml specifying vulnerabilities to ignore --"
  GRYPE_CONF_FILE=".grype.yaml"
  touch $GRYPE_CONF_FILE
  echo "ignore:" > $GRYPE_CONF_FILE

  IFS=','; for VULN_ID in $ALLOW_VULNS; do
      echo "Ignoring vulnerability with id $VULN_ID"
      echo "    - vulnerability: $VULN_ID" >> $GRYPE_CONF_FILE
  done
  echo "------------------------------------"
fi

echo "-- Scanning dependency for vulnerabilities --"
./$SBOM_DIR/grype sbom:$sbom_path --fail-on low
echo "---------------------------------------------"
echo "<<<< Done scanning SBOM"
