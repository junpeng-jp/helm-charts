#!/bin/sh
set -eu

apk add --no-cache git >/dev/null

IS_SSH=
case "$REPO_URL" in git@*|ssh://*) IS_SSH=1 ;; esac

rm -f /config/.gitops/known_hosts /config/.gitops/ssh_config
rm -rf /config/.gitops/allowed-signers
mkdir -p /config/.gitops/allowed-signers /config/.gitops/state

if [ -n "$IS_SSH" ]; then
  printf '%s' "$KNOWN_HOSTS" > /config/.gitops/known_hosts
  {
    printf '%s\n' 'Host *'
    printf '%s\n' '  IdentityFile /run/secrets/gitops/ssh_key'
    printf '%s\n' '  UserKnownHostsFile /config/.gitops/known_hosts'
    printf '%s\n' '  StrictHostKeyChecking yes'
    printf '%s\n' '  IdentitiesOnly yes'
  } > /config/.gitops/ssh_config
fi

git init "/config/gitops/${REPO_NAME}"
(
  cd "/config/gitops/${REPO_NAME}"
  git remote set-url origin "$REPO_URL" 2>/dev/null || \
    git remote add origin "$REPO_URL"
  if [ -n "$IS_SSH" ]; then
    git config core.sshCommand 'ssh -F /config/.gitops/ssh_config'
  fi
  if [ -n "${ALLOWED_SIGNERS:-}" ]; then
    printf '%s' "$ALLOWED_SIGNERS" > "/config/.gitops/allowed-signers/${REPO_NAME}"
    git config gpg.ssh.allowedSignersFile "/config/.gitops/allowed-signers/${REPO_NAME}"
  fi
  git ls-remote origin HEAD >/dev/null
)

printf '%s' "$REPO_URL"  > /config/.gitops/state/gitops_repo_url
printf '%s' "$REPO_NAME" > /config/.gitops/state/gitops_repo_name
touch /config/.gitops/state/gitops_sync_ref
touch /config/.gitops/state/gitops_last_sync

mkdir -p /config/gitops/packages
cp /run/gitops-configmap/git_sync.sh /config/gitops/git_sync.sh
chmod 755 /config/gitops/git_sync.sh
cp /run/gitops-configmap/shell.yaml \
   /run/gitops-configmap/script.yaml \
   /run/gitops-configmap/sensor.yaml \
   /config/gitops/packages/
