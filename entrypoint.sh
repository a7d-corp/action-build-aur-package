#!/usr/bin/env bash

set -o errexit
set -o pipefail

main() {
  # sanity check required files
  check_requirements

  # prep SSH
  prepare_ssh

  # pick up variables needed to run
  source VARS.env

  # get tag of the latest version
  LATEST_TAG=$(get_latest_version "${UPSTREAM_REPO}")
  check_response "${LATEST_TAG}" LATEST_TAG

  # pick up the version of the last package build
  source VERSION.env

  ## compare version to version.txt
  compare_versions "${CURRENT_VERSION}" "${LATEST_TAG}"

  # get the asset download url
  ASSET_URL=$(get_asset_url "${UPSTREAM_REPO}" "${ASSET_FILE_STUB}")
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

  # update pkgbuild with sha256sum and version
  sed -i "s/^pkgver.*/pkgver=${LATEST_TAG}/g" PKGBUILD
  sed -i "s/^sha256sums.*/sha256sums=('${ASSET_SHA}')/g" PKGBUILD

  # drop pkgrel back to 1
  sed -i "s/^pkgrel.*/pkgrel=1/g" PKGBUILD

  # check pkgbuild with namcap
  if ! namcap PKGBUILD ; then
    err "PKGBUILD failed namcap check"
  fi

  # build package
  makepkg

  # check package file with namcap
  find -name \*pkg.tar.zst -exec namcap {} \;

  # test installing package
  find -name \*pkg.tar.zst -exec pacman -U {} \;

  # update .SRCINFO
  makepkg --printsrcinfo > .SRCINFO

  # prepare git config
  git config --global user.email "${GIT_EMAIL}"
  git config --global user.name "${GIT_USER}"

  if ! git add PKGBUILD .SRCINFO ; then
    err "Couldn't add files for committing"
  fi

  git commit -m "bump to ${LATEST_TAG}"

  if ! git push ; then
    err "Couldn't push commit to the AUR"
  fi
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

prepare_ssh() {
  # prepares the container for SSH

  if [ ! -d $HOME/.ssh ] ; then
    mkdir -m 0700 $HOME/.ssh
  fi

  # pull down the public key(s) from the AUR servers
  if ! ssh-keyscan aur.archlinux.org > $HOME/.ssh/known_hosts ; then
    err "Couldn't get SSH public key from AUR servers"
  fi

  # write the private SSH key out to disk
  if [ ! -z "${AUR_SSH_KEY}" ] ; then
    echo "${AUR_SSH_KEY}" > $HOME/.ssh/ssh_key
    chmod 0400 $HOME/.ssh/ssh_key
  fi
}

check_response() {
  # takes two inputs and calls err() if the variable is empty
  # $1 - variable name (for logging)
  # $2 - variable value (for checking)

  [ ! -z "${1}" ] || err "${2} is an empty var"
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

  if [ ! -z "${PERSONAL_ACCESS_TOKEN}" ]; then
    curl --silent \
      -H "Authorization: token ${PERSONAL_ACCESS_TOKEN}"
      "https://api.github.com/repos/${1}/releases/latest" \
      | jq -r --arg ASSET_FILE "${2}" \
      '.assets[] | select(.name | contains($ASSET_FILE)) | .browser_download_url'
  else
    curl --silent \
      "https://api.github.com/repos/${1}/releases/latest" \
      | jq -r --arg ASSET_FILE "${2}" \
      '.assets[] | select(.name | contains($ASSET_FILE)) | .browser_download_url'
  fi
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
