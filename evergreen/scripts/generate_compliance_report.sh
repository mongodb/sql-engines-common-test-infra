#!/bin/bash

set -o errexit

echo "Author = ${author}"
echo "Author email = ${author_email}"
echo "Version = ${release_version}"

SBOM_URL="https://translators-connectors-releases.s3.amazonaws.com/${working_dir}/${SBOM_FILENAME}"
SARIF_URL="https://translators-connectors-releases.s3.amazonaws.com/${working_dir}/${STATIC_CODE_ANALYSIS_NAME}"

echo "Sbom url = $SBOM_URL"
echo "Sarif Url = $SARIF_URL"

echo "----- Generating ${COMPLIANCE_REPORT_NAME} -----"

# Copy template
echo "Copying template file from ${resources_dir}/compliance_report_template.md to ${COMPLIANCE_REPORT_NAME}"
cp ${resources_dir}/compliance_report_template.md ${COMPLIANCE_REPORT_NAME}

# Update the version
echo "Update the version"
echo "sed -i.bu "s,%VERSION%,${release_version},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%VERSION%,${release_version},g" ${COMPLIANCE_REPORT_NAME}

# Update the SBOM link
echo "Update the SBOM link"
echo "sed -i.bu "s,%SBOM_URL%,$SBOM_URL,g"${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%SBOM_URL%,$SBOM_URL,g" ${COMPLIANCE_REPORT_NAME}

# Update the SARIF link
echo "Update the SARIF link"
echo "sed -i.bu "s,%SARIF_URL%,$SARIF_URL,g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%SARIF_URL%,$SARIF_URL,g" ${COMPLIANCE_REPORT_NAME}

# Update the author information
echo "Update the author name"
echo "sed -i.bu "s,%AUTHOR%,${author},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%AUTHOR%,${author},g" ${COMPLIANCE_REPORT_NAME}

echo "update the author email"
echo "sed -i.bu "s,%AUTHOR_EMAIL%,${author_email},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%AUTHOR_EMAIL%,${author_email},g" ${COMPLIANCE_REPORT_NAME}
echo "---------------------------"

# Update the created date
CREATED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Created date = $CREATED_DATE"
echo "update the created date"
echo "sed -i.bu "s,%CREATED_DATE%,${CREATED_DATE},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%CREATED_DATE%,${CREATED_DATE},g" ${COMPLIANCE_REPORT_NAME}
echo "---------------------------"

# update repository specific metadata
echo "update the product name"
echo "sed -i.bu "s,%PRODUCT_NAME%,${product_name},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%PRODUCT_NAME%,${product_name},g" ${COMPLIANCE_REPORT_NAME}
echo "---------------------------"

echo "update the repo name"
echo "sed -i.bu "s,%REPO_NAME%,${repo_name},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%REPO_NAME%,${repo_name},g" ${COMPLIANCE_REPORT_NAME}
echo "---------------------------"

echo "update the link to signing verification instructions"
echo "sed -i.bu "s,%SIGNING_SECTION_BOOKMARK%,${signing_section_bookmark},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%SIGNING_SECTION_BOOKMARK%,${signing_section_bookmark},g" ${COMPLIANCE_REPORT_NAME}
echo "---------------------------"
