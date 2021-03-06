#!/bin/bash

set -o errexit

# shellcheck source=./build.properties
source ./build.properties
# shellcheck source=./checksum.properties
source=./checksum.properties

declare -r DOWNLOAD_DIR='.'

# Get Java release from Docker tag (e.g. 8u181)
JAVA_VERSION="${DOCKER_IMAGE_TAG%%-[![:digit:]]*}"

# Remove periods, and replace remaining non-alphanumerics with underscores (e.g. 8u181, 10_2018_03_20)
JAVA_VERSION_CLEANED=$(echo "${JAVA_VERSION}" | sed -e 's/\.//g' -e 's%[^[:alnum:]]%_%g')
# bash 3.2 compatible alternative to associative arrays
JRE_CHECKSUM_256_REF="JRE_CHECKSUM_256_${JAVA_VERSION_CLEANED}"

# Alfresco Repo
# Stored like "linux-x64:serverjre:8u181:tar.gz:bin"
MVN_REPO_URL=https://artifacts.alfresco.com/nexus/content/repositories/oracle-java
# Mavenise me
GROUP_ID="${JAVA_OS_ARCH}"
ARTIFACT_ID="${JAVA_SE_TYPE}"
JAVA_BASENAME="${JAVA_SE_TYPE}-${JAVA_VERSION}-bin.${JAVA_PACKAGING}"

CHECKSUM="${CHECKSUM_256["${GROUP_ID}":"${ARTIFACT_ID}":"${JAVA_VERSION}":"${JAVA_PACKAGING}"]}"


java::download::artifacts::mvn () {
    # As Oracle have made downloading non-current versions of Java difficult,
    # we are sadly having to store them in an internal repository.

    # Use Maven 3
    unset M2_HOME
    export M3_HOME=/opt/apache-maven

    "${M3_HOME}"/bin/mvn org.apache.maven.plugins:maven-dependency-plugin:3.0.2:copy \
        --quiet \
        -DrepoUrl="${MVN_REPO_URL}" \
        -Dartifact="${GROUP_ID}":"${ARTIFACT_ID}":"${JAVA_VERSION}":"${JAVA_PACKAGING}":bin \
        -DoutputDirectory="${DOWNLOAD_DIR}"

    # Our filenames are munged into Maven compatible names
    JRE_FILENAME="${DOWNLOAD_DIR}/${JAVA_BASENAME}"
}

java::download::artifacts::curl () {
    # Also uses artifacts.alfresco.com but via curl
    declare OLD_PWD="${PWD}"
    cd "${DOWNLOAD_DIR}"
    curl -sSLO --user "${ARTIFACTS_USER}:${ARTIFACTS_PASSWORD}"  "${MVN_REPO_URL}/${GROUP_ID}/${ARTIFACT_ID}/${JAVA_BASENAME}"

    JRE_FILENAME="${DOWNLOAD_DIR}/${JAVA_BASENAME}"
}

java::download::openjdk::curl () {
    # You can still download the latest Java version from Oracle

    declare OLD_PWD="${PWD}"
    cd "${DOWNLOAD_DIR}"
    # https://download.java.net/java/GA/jdk11/28/GPL/openjdk-11+28_linux-x64_bin.tar.gz
    # https://download.java.net/java/GA/jdk11/28/GPL/openjdk-11+28_linux-x64_bin.tar.gz.sha256
    curl -sSLO "${JRE_URL}"
    cd "${OLD_PWD}"

    JRE_FILENAME="${DOWNLOAD_DIR}/${JRE_URL##*/}"
}

java::download::oracle::curl () {
    # You can still download the latest Java version from Oracle

    declare OLD_PWD="${PWD}"
    cd "${DOWNLOAD_DIR}"
    curl -jksSLOH "Cookie: oraclelicense=accept-securebackup-cookie" "${JRE_URL}"
    cd "${OLD_PWD}"

    JRE_FILENAME="${DOWNLOAD_DIR}/${JRE_URL##*/}"
}

# Wrapper
java::download () {
    if [ "${USE_MVN}" = 'true' ]; then
        java::download::artifacts::mvn
    elif [ "${USE_CURL}" = 'true' ]; then
        java::download::artifacts::curl; then
    elif [ "${USE_OPENJDK}" = 'true' ]; then
        java::download::openjdk::curl
    else
        java::download::oracle::curl
    fi
}

java::checksum () {
    # Check for coreutils version first
    # Note: two spaces are required between the variables in some implementations

    if [ -x "$(command -v sha256sum)" ]; then
        echo "${CHECKSUM}  ${JRE_FILENAME}" | sha256sum -c - > /dev/null
    elif [ -x "$(command -v gsha256sum)" ]; then
        echo "${CHECKSUM}  ${JRE_FILENAME}" | gsha256sum -c - > /dev/null
    else
        echo "${CHECKSUM}  ${JRE_FILENAME}" | shasum -a 256 -c - > /dev/null
    fi
}

# Just echo the filename to STDOUT
java::print_java_pkg () {
    basename "${JRE_FILENAME}"
}

main() {
    java::download
    java::checksum
    java::print_java_pkg
}

# Call main() if we're not sourced
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"