
resources_dir: ./evergreen/resources
PRODUCT_NAME: ${PRODUCT_NAME}
COMPLIANCE_REPORT_NAME: "${PRODUCT_NAME}-${release_version}-compliance-report.md"
SBOM_LICENSES: "${PRODUCT_NAME}.licenses.cdx.json"
STATIC_CODE_ANALYSIS_NAME: "${PRODUCT_NAME}-${release_version}.sast.sarif"
SBOM_FILENAME: "${PRODUCT_NAME}-${release_version}.sbom.json"
AUGMENTED_SBOM_FILENAME: "${PRODUCT_NAME}-${release_version}.augmented.sbom.json"

prepare_shell: |
  set -o errexit
  export PRODUCT_NAME="$PRODUCT_NAME"
  export COMPLIANCE_REPORT_NAME="$COMPLIANCE_REPORT_NAME"
  export SBOM_LICENSES="$SBOM_LICENSES"
  export STATIC_CODE_ANALYSIS_NAME="$STATIC_CODE_ANALYSIS_NAME"
  export SBOM_FILENAME="$SBOM_FILENAME"
  export AUGMENTED_SBOM_FILENAME="$AUGMENTED_SBOM_FILENAME"
EOT
