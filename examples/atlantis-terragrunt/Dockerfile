############################################################
# Atlantis image with terragrunt and orca-cli baked in.
#
# The stock Atlantis image ships Terraform and Conftest but neither Terragrunt
# nor orca-cli, and the workflow needs both on PATH.
#
# Build and push to your own registry, then point your Atlantis deployment at
# it. Do not install tools at workflow runtime — a `run` step that curls a
# binary on every plan is both slow and an unpinned supply-chain dependency in
# the middle of your security gate.
############################################################

ARG ATLANTIS_VERSION=v0.46.0

# The -debian variant, not the default alpine one: the orca-cli installer
# fetches a glibc-linked binary.
FROM ghcr.io/runatlantis/atlantis:${ATLANTIS_VERSION}-debian

ARG TERRAGRUNT_VERSION=v1.1.1

# `set -o pipefail` needs bash, and the orca-cli install is a pipeline.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) tg_arch=amd64 ;; \
      arm64) tg_arch=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/download/${TERRAGRUNT_VERSION}/terragrunt_linux_${tg_arch}"; \
    chmod 0755 /usr/local/bin/terragrunt; \
    terragrunt --version

# orca-cli. The installer is fetched from an unpinned branch, which is worth
# knowing about: for a hardened build, pin to a release tag instead of `main`
# and verify the downloaded binary against the cosign public key the orca-cli
# repo publishes (orca_cli_cosign_public_key.pub) before trusting it.
RUN set -eux; \
    curl -sfL 'https://raw.githubusercontent.com/orcasecurity/orca-cli/main/install.sh' \
      | bash -s -- -b /usr/local/bin; \
    orca-cli --version

USER atlantis
