#!/bin/bash

set -o errexit

echo "Author = ${author}"
echo "Author email = ${author_email}"
echo "Version = ${release_version}"

SBOM_URL="https://translators-connectors-releases.s3.amazonaws.com/eap/${working_dir}/${working_dir}-${release_version}.sbom.json"
SARIF_URL="https://translators-connectors-releases.s3.amazonaws.com/eap/${working_dir}/${working_dir}-${release_version}.sast.sarif"

echo "Sbom url = $SBOM_URL"
echo "Sarif Url = $SARIF_URL"

echo "----- Generating ${COMPLIANCE_REPORT_NAME} -----"

# Copy template
echo "Copying template file from ${template_filepath} to ${COMPLIANCE_REPORT_NAME}"
cp ${template_filepath} ${COMPLIANCE_REPORT_NAME}

# Update the version
echo "Update the version"
echo "sed -i.bu "s,%VERSION%,${version},g" ${COMPLIANCE_REPORT_NAME}"
sed -i.bu "s,%VERSION%,${version},g" ${COMPLIANCE_REPORT_NAME}

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