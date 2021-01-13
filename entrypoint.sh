#!/usr/bin/env bash

set -o errexit
set -o pipefail

main() {
  # set working directory to the workdir provided in the workflow config
  WORKDIR="$(pwd)/${INPUT_WORKDIR}"

  # all further operations are relative to this directory
  cd "${WORKDIR}"

  # sanity check required files
  check_requirements

  # install any additional packages provided in the workflow config
  if [ ! -z "${INPUT_ADDITIONALPACKAGES}" ] ; then
    install_packages "${INPUT_ADDITIONALPACKAGES}"
  fi

  # expose additional packages installed to the workflow output
  set_output "ADDITIONAL_PACKAGES" "${INPUT_ADDITIONAL_PACKAGES}"

  # prep SSH
  prepare_ssh

  # pick up variables needed to run
  source VARS.env

  # get tag of the latest version
  log "Getting latest tag from Github API"
  LATEST_TAG=$(get_latest_version "${UPSTREAM_REPO}")
  check_response "${LATEST_TAG}" LATEST_TAG

  # pick up the version of the last package build
  source VERSION.env

  # expose the current version to the workflow output
  set_output "CURRENT_VER" "${CURRENT_VER}"

  # expose the latest vresion to the workflow output
  set_output "LATEST_VER" "${LATEST_TAG}"

  # compare version to version.txt
  log "Comparing latest version to current version"
  compare_versions "${CURRENT_VERSION}" "${LATEST_TAG}"

  # get the asset download url
  log "Getting asset URL from Github API"
  ASSET_URL=$(get_asset_url "${UPSTREAM_REPO}" "${ASSET_FILE_STUB}")
  check_response "${ASSET_URL}" ASSET_URL

  # expose the asset URL to the workflow output
  set_output "ASSET_URL" "${ASSET_URL}"

  # download the asset file
  log "Downloading asset file from Github"
  wget -q "${ASSET_URL}" -O tmp_asset_file

  # sha256sum the asset file
  log "Compute sha256sum of the asset file"
  ASSET_SHA=$(sha256sum tmp_asset_file | cut -d ' ' -f 1)
  check_response "${ASSET_SHA}" ASSET_SHA

  # expose the asset file SHA to the workflow output
  set_output "ASSET_SHA" "${ASSET_SHA}"

  # clone aur repo
  log "Cloning AUR repo into ./aur_repo"
  export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=$HOME/.ssh/known_hosts -i $HOME/.ssh/ssh_key"
  if ! git clone "${AUR_REPO}" aur_repo; then
    err "failed to clone AUR repo"
  fi

  # set ownership on the cloned repo so we can run as nonroot later
  chown -R notroot.notroot aur_repo

  # move into the AUR checkout
  cd aur_repo

  # update pkgbuild with sha256sum and version
  log "Updating PKGBUILD"
  sed -i "s/^pkgver.*/pkgver=${LATEST_TAG}/g" PKGBUILD
  sed -i "s/^sha256sums.*/sha256sums=('${ASSET_SHA}')/g" PKGBUILD

  # drop pkgrel back to 1
  sed -i "s/^pkgrel.*/pkgrel=1/g" PKGBUILD

  # check pkgbuild with namcap
  log "Testing PKGBUILD with namcap"
  if ! namcap PKGBUILD ; then
    err "PKGBUILD failed namcap check"
  fi
 sleep 10h
  # build package as non-root user
  log "Building package file as user notroot"
  su notroot -c "makepkg"

  # store the package file name
  BUILT_PKG_FILE=$(find -name \*pkg.tar.zst)

  # ensure a filename was discovered
  check_response "${BUILT_PKG_FILE}" "BUILT_PKG_FILE"

  # expose the built package name to the workflow output
  set_output "BUILT_PKG_FILE" "${BUILT_PKG_FILE}"

  # check package file with namcap
  log "Testing package file with namcap"
  namcap "${BUILT_PKG_FILE}"

  # test installing package
  log "Installing built package"
  pacman -U "${BUILT_PKG_FILE}"

  # prepare git config
  git config --global user.email "${GIT_EMAIL}"
  git config --global user.name "${GIT_USER}"

  # expose putToAur value to workflow output
  set_output "PUSH_TO_AUR" "${INPUT_PUSH_TO_AUR}"

  # if pushToAur input is 'true'
  if [ "${INPUT_PUSHTOAUR}" == "true" ] ; then
    # update .SRCINFO
    log "Updating .SRCINFO"
    makepkg --printsrcinfo > .SRCINFO

    # add files for committing
    log "Staging files for committing"
    if ! git add PKGBUILD .SRCINFO ; then
      err "Couldn't add files for committing"
    fi

    # commit changes
    log "Committing changes to AUR repo"
    git commit -m "bump to ${LATEST_TAG}"

    sleep 10h
    exit 0

    # push changes to the AUR
    log "Pushing commit to AUR repo"
    if ! git push ; then
      err "Couldn't push commit to the AUR"
    fi
  fi

  # change directory back to the working directory
  cd "${WORKDIR}"

  # update repo with the latest built version
  echo "CURRENT_VERSION=${LATEST_TAG}" > VERSION.env

  # add the updated file for committing
  log "Staging VERSION.env for committing"
  if ! git add VERSION.env ; then
    err "Couldn't add VERSION.env"
  fi

  # commit the file back
  log "Committing changes"
  git commit -m "update latest version to ${LATEST_TAG}"

  # don't use AUR-specific SSH command
  unset GIT_SSH_COMMAND

  # push changes to the repo
  log "Pushing changes to source repo"
  if ! git push ; then
    err "Couldn't push commit"
  fi
}

# helper functions
log() {
  echo "INFO: $@"
}

err() {
  echo "ERROR: $@"
  exit 1
}

set_output() {
  # takes two inputs and logs to stdout
  # $1 - output name to set
  # $2 - value of output to set
  echo "::set-output name=${1}::${2}"
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

  # expose the vars to the workflow output
  set_output "UPSTREAM_REPO" "${UPSTREAM_REPO}"
  set_output "AUR_REPO" "${AUR_REPO}"
  set_output "PKG_NAME" "${PKG_NAME}"
  set_output "ASSET_FILE_STUB" "${ASSET_FILE_STUB}"
}

install_packages() {
  # takes one input and exits non-zero if packages fail to install
  # $1 - space-separated list of packages to install
  log "Installing additional packages"
  if ! pacman -Syuq --noconfirm --noconfirm "${1}" ; then
    err "Failed to install additional packages"
  fi
}

prepare_ssh() {
  # prepares the container for SSH
  log "Preparing the container for SSH"

  if [ ! -d $HOME/.ssh ] ; then
    log "Creating $HOME/.ssh"
    mkdir -m 0700 $HOME/.ssh
  fi

  # pull down the public key(s) from the AUR servers
  log "Collecting SSH public key(s) from AUR server(s)"
  if ! ssh-keyscan -H aur.archlinux.org > $HOME/.ssh/known_hosts ; then
    err "Couldn't get SSH public key from AUR servers"
  fi

  # write the private SSH key out to disk
  if [ ! -z "${AUR_SSH_KEY}" ] ; then
    # write the key out to disk
    log "Writing AUR SSH key to $HOME/.ssh/ssh_key"
    echo "${AUR_SSH_KEY}" > $HOME/.ssh/ssh_key

    # ensure correct permissions
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
