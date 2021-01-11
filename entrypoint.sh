#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

main() {
  # sanity check required files
  check_requirements

  # pick up variables needed to run
  source VARS.env

  # get tag of the latest version
  LATEST_TAG=$(get_latest_version "${REPO}")
  check_response "${LATEST_TAG}" LATEST_TAG

  # pick up the version of the last package build
  source VERSION.env

  ## compare version to version.txt
  compare_versions "${CURRENT_VERSION}" "${LATEST_TAG}"

  # get the asset download url
  ASSET_URL=$(get_asset_url "${REPO}" "${ASSET_FILE}")
  check_response "${ASSET_URL}" ASSET_URL

  # download the asset file
  wget "${ASSET_URL}" -O tmp_asset_file

  # sha256sum the asset file
  ASSET_SHA=$(sha256sum tmp_asset_file)
  check_response "${ASSET_SHA}" ASSET_SHA

  # clone aur repo
  if ! git clone "${AUR_REPO}" aur_repo; then
    err "failed to clone AUR repo"
  fi

  # move into the AUR checkout
  cd aur_repo

  ## update pkgbuild with sha256sum and version
  ## drop pkgrel if updating version

  #namcap pkgbuild
  #build pkg file
  #namcap pkg file
  #install
  #update .SRCINFO
  #commit
  #push
}

# helper functions
log() {
  level=$1
  shift 1
  date -u +"%Y-%m-%dT%H:%M:%SZ" | tr -d '\n'
  echo " [${level}] $@"
}

info() {
  log "INFO" "$@"
}

err() {
  log "ERROR" "$@"
  exit 1
}

check_requirements() {
  # check file containing last bult version number exists
  [ -f VERSION.env ] || err "VERSION.env file not found"

  # check the version is in the file
  if ! grep -q "CURRENT_VERSION" VERSION.env; then
    err "CURRENT_VERSION not found in VERSION.env file"
  fi

  # check the vars file exists
  [ -f VARS.env ] || err "VARS.ENV file not found"

  # check the vars file contains the requirements
  if ! grep -qE 'UPSTREAM|AUR|PKG|STUB' VARS.env; then
    err "required variable not set in VARS.env file"
  fi
}

check_response() {
  # takes two inputs and calls err() if the variable is empty
  # $1 - variable name (for logging)
  # $2 - variable value (for checking)

  [ ! -z "${2}" ] || err "${1} is an empty var"
}

get_latest_version() {
  # takes one input and returns tag name for latest release
  # $1 - repo in format 'org/repo'

  curl --silent \
    "https://api.github.com/repos/${1}/releases/latest" \
    | jq -r .tag_name
}

get_asset_url() {
  # takes two inputs and returns download URL for asset file
  # $1 - repo in format 'org/repo'
  # $2 - asset file name stub to match

  curl --silent \
    "https://api.github.com/repos/${1}/releases/latest" \
    | jq -r --arg ASSET_FILE "${2}" \
    '.assets[] | select(.name | contains($ASSET_FILE)) | .browser_download_url'
}

compare_versions() {
  # takes two version strings and compares them (stripping leading 'v' if required)
  # $1 - previous package version string
  # $2 - latest package version string

  if [[ "${1#v}" == "${2#v}" ]]; then
    log "latest upstream version is the same as the current package version, nothing to do"
    exit 0
  fi
}

# run
main "$@"
