#!/bin/sh
set -eu

REPO_NAME="${1:?Usage: git_sync.sh <repo_name> [--branch=<branch>] [--tag=<tag>]}"
shift

BRANCH=""
TAG=""

for arg in "$@"; do
  case "$arg" in
    --branch=*) BRANCH="${arg#--branch=}" ;;
    --tag=*)    TAG="${arg#--tag=}" ;;
    *) echo "ERROR: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [ -n "$TAG" ] && [ -n "$BRANCH" ]; then
  echo "ERROR: --tag and --branch are mutually exclusive" >&2
  exit 1
fi

REPO_DIR="/config/gitops/${REPO_NAME}"
TARGET_DIR="${TARGET_DIR:-/config/packages/${REPO_NAME}}"

cd "$REPO_DIR"

git fetch --prune --tags origin

if [ -n "$TAG" ]; then
  REF=$(git rev-parse "refs/tags/${TAG}") || {
    echo "ERROR: tag ${TAG} not found" >&2
    exit 1
  }
else
  BRANCH="${BRANCH:-main}"
  REF=$(git rev-parse "origin/${BRANCH}") || {
    echo "ERROR: branch ${BRANCH} not found on remote" >&2
    exit 1
  }
fi

if git config gpg.ssh.allowedSignersFile >/dev/null 2>&1; then
  git verify-commit "$REF" || {
    echo "ERROR: commit signature verification failed for ${REF}" >&2
    exit 1
  }
fi

STAGING="/config/gitops/.tmp/${REPO_NAME}"
rm -rf "$STAGING"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

git archive "$REF" | tar -x -C "$STAGING"

mkdir -p "$TARGET_DIR"
rsync -a --safe-links --delete "$STAGING/" "$TARGET_DIR/"

SHORT_REF=$(git rev-parse --short "$REF")
REF_VALUE="${TAG:-${BRANCH}}"

printf '%s' "${SHORT_REF} (${REF_VALUE})" > /config/.gitops/state/gitops_sync_ref
printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /config/.gitops/state/gitops_last_sync
echo "Synced ${SHORT_REF} (${REF_VALUE}) to ${TARGET_DIR}"
