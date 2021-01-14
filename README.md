# action-build-aur-package

This action uses a purpose-built [image](https://hub.docker.com/repository/docker/glitchcrab/arch-build-container)
to sanity-check, build and test an AUR package when it the upstream repository
publishes a new release. It optionally pushes the update to the Arch User Repository.

---

## Example usage

Build and push from a subdirectory in the repository:

```yaml
      - name: build, test and push package
        uses: glitchcrab/action-build-aur-package@main
        with:
          workdir: "./packagename-bin"
          pushToAur: true
        env:
          AUR_SSH_KEY: ${{ secrets.AUR_SSH_KEY }}
          GIT_EMAIL: ${{ secrets.GIT_EMAIL }}
          GIT_USER: ${{ secrets.GIT_USER }}
```

Install additional packages required to build the package:

```yaml
      - name: build, test and push package
        uses: glitchcrab/action-build-aur-package@main
        with:
          workdir: "./packagename-bin"
          pushToAur: true
	  additionalPackages: "golangci-lint-bin go"
        env:
          AUR_SSH_KEY: ${{ secrets.AUR_SSH_KEY }}
          GIT_EMAIL: ${{ secrets.GIT_EMAIL }}
          GIT_USER: ${{ secrets.GIT_USER }}
```

## Inputs

### `additionalPackages`

- Description: 'Space-separated list of additional packages to install'
- Required: false
- Default: ''

### `pushToAur`

- Description: 'Push changes to the AUR'
- Required: false
- Default: false

### `workdir`

- Description: 'The directory to work in'
- Required: false
- Default: './'

## Secrets

Various secrets must be configured in the repo for this action to complete.

### `AUR_SSH_KEY`

- Description: 'SSH private key with permissions to push to the AUR'
- Required: true

### `GITHUB_EMAIL`

- Description: 'Username to configure Git with'
- Required: true

### `GITHUB_USER`

- Description: 'Email to configure Git with'
- Required: true
