#!/usr/bin/env bash
# sync.sh — fetch a git ref, validate with check_config, copy on success
#
# Usage:
#   sync.sh --repo <name> --ref <tag-or-hash> --copy <src>:<dst> [--copy ...]
#
# Arguments:
#   --repo    name of the repo under /config/gitops/ (e.g. ha-config)
#   --ref     tag name or commit hash to check out
#   --copy    colon-separated source:destination pair; may be repeated
#             src is relative to the checkout root
#             dst is an absolute path
#
# Example:
#   sync.sh --repo ha-config --ref v1.2.3 \
#     --copy automations/:/config/automations/ \
#     --copy scripts/:/config/scripts/

set -euo pipefail

GITOPS_DIR="/config/gitops"
CHECK_DIR="/run/ha-check"

REPO_NAME=""
REF=""
declare -a COPIES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO_NAME="$2"; shift 2 ;;
    --ref)   REF="$2";       shift 2 ;;
    --copy)  COPIES+=("$2"); shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$REPO_NAME" ] && { echo "--repo is required" >&2; exit 1; }
[ -z "$REF" ]       && { echo "--ref is required"  >&2; exit 1; }
[ ${#COPIES[@]} -eq 0 ] && { echo "at least one --copy is required" >&2; exit 1; }

REPO_DIR="$GITOPS_DIR/$REPO_NAME/repo.git"
REMOTE_FILE="$GITOPS_DIR/$REPO_NAME/remote"

[ ! -f "$REMOTE_FILE" ] && { echo "No remote file at $REMOTE_FILE" >&2; exit 1; }
REPO_URL="$(cat "$REMOTE_FILE")"

# Only SSH (git@) and HTTPS remotes are permitted; plaintext HTTP is rejected.
case "$REPO_URL" in
  git@*|https://*) ;;
  *) echo "ERROR: only SSH (git@) and HTTPS remote URLs are allowed (got: $REPO_URL)" >&2; exit 1 ;;
esac

# Hardened SSH: use only the deploy key, require host verification, no interactive prompts.
export GIT_SSH_COMMAND="ssh \
  -i /run/secrets/gitops/id_ed25519 \
  -o UserKnownHostsFile=/run/secrets/gitops/known_hosts \
  -o StrictHostKeyChecking=yes \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ForwardAgent=no \
  -o ForwardX11=no \
  -o PermitLocalCommand=no"

# --- 1. Clone or fetch ---
if [ ! -d "$REPO_DIR" ]; then
  git clone --bare --depth 1 "$REPO_URL" "$REPO_DIR"
  git -C "$REPO_DIR" config gc.reflogExpire 0
  git -C "$REPO_DIR" config gc.reflogExpireUnreachable 0
fi

git -C "$REPO_DIR" fetch --depth 1 origin "$REF"

# --- 2. Verify commit/tag signature if allowed_signers is provided ---
SIGNERS=/run/secrets/gitops/allowed_signers
if [ -f "$SIGNERS" ]; then
  git -C "$REPO_DIR" config gpg.format ssh
  git -C "$REPO_DIR" config gpg.ssh.allowedSignersFile "$SIGNERS"
  if git -C "$REPO_DIR" cat-file -t "refs/tags/$REF" 2>/dev/null | grep -q "^tag$"; then
    git -C "$REPO_DIR" verify-tag "$REF" \
      || { echo "ERROR: tag signature verification failed for $REF" >&2; exit 1; }
  else
    git -C "$REPO_DIR" verify-commit FETCH_HEAD \
      || { echo "ERROR: commit signature verification failed" >&2; exit 1; }
  fi
fi

# --- 3. Prune — keep only the fetched commit ---
git -C "$REPO_DIR" reflog expire --expire=now --all
git -C "$REPO_DIR" gc --prune=now --quiet

# --- 4. Worktree checkout into tmpfs ---
git -C "$REPO_DIR" worktree prune
# $CHECK_DIR is a Kubernetes emptyDir mount point; rm -rf the path itself would hit EBUSY.
# Clear contents only, then let git worktree add populate the empty directory.
find "$CHECK_DIR" -mindepth 1 -delete 2>/dev/null || true
git -C "$REPO_DIR" worktree add --detach "$CHECK_DIR" FETCH_HEAD
chmod 700 "$CHECK_DIR"
trap 'git -C "$REPO_DIR" worktree remove --force "$CHECK_DIR" 2>/dev/null' EXIT

# --- 5. Symlink live config files not present in the checkout ---
for item in /config/*; do
  name=$(basename "$item")
  [ ! -e "$CHECK_DIR/$name" ] && ln -s "$item" "$CHECK_DIR/$name"
done

# --- 6. Validate ---
hass --script check_config -c "$CHECK_DIR"

# --- 7. Copy to destinations ---
for pair in "${COPIES[@]}"; do
  src="${pair%%:*}"
  dst="${pair#*:}"
  src_path="$CHECK_DIR/$src"
  [ ! -e "$src_path" ] && { echo "Source not found in checkout: $src" >&2; exit 1; }
  cp -a "$src_path" "$dst"
done

echo "Sync complete: $REPO_NAME @ $REF"
