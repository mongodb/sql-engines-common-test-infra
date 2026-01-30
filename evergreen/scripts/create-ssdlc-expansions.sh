export SBOM_DIR="sbom_tools"
export PRODUCT_NAME="${PRODUCT_NAME}"
export COMPLIANCE_REPORT_NAME="${PRODUCT_NAME}-${release_version}-compliance-report.md"
export STATIC_CODE_ANALYSIS_NAME="${PRODUCT_NAME}-${release_version}.sast.sarif"
export SBOM_FILENAME="${PRODUCT_NAME}-${release_version}.sbom.json"
export SBOM_LICENSES="${PRODUCT_NAME}.licenses.cdx.json"
export SBOM_VULN="${PRODUCT_NAME}-${release_version}.merge.grype.cdx.json"
export AUGMENTED_SBOM_FILENAME="${PRODUCT_NAME}-${release_version}.augmented.sbom.json"

cat <<EOT >${working_dir}/ssdlc-expansions.yml
SBOM_DIR: "$SBOM_DIR"
PRODUCT_NAME: "$PRODUCT_NAME"
COMPLIANCE_REPORT_NAME: "$COMPLIANCE_REPORT_NAME"
STATIC_CODE_ANALYSIS_NAME: "$STATIC_CODE_ANALYSIS_NAME"
SBOM_FILENAME: "$SBOM_FILENAME"
SBOM_LICENSES: "$SBOM_LICENSES"
SBOM_VULN: "$SBOM_VULN"
AUGMENTED_SBOM_FILENAME: "$AUGMENTED_SBOM_FILENAME"
EOT
