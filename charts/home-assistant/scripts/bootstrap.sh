#!/bin/sh
set -eu

if [ "${HACS_ENABLED}" = "true" ]; then
  URL="https://github.com/hacs/integration/releases/download/${HACS_VERSION}/hacs.zip"
  if [ ! -d /config/custom_components/hacs ]; then
    apk add -q --no-progress unzip
    wget -q -O /tmp/hacs.zip "$URL"
    if [ -n "${HACS_SHA256:-}" ]; then
      printf '%s  /tmp/hacs.zip\n' "${HACS_SHA256}" | sha256sum -c - || {
        rm -f /tmp/hacs.zip
        echo "ERROR: HACS integrity check failed for version ${HACS_VERSION}" >&2
        exit 1
      }
    fi
    unzip -q /tmp/hacs.zip -d /config/custom_components/hacs
    rm /tmp/hacs.zip

    # .HA_VERSION is written by HA on first start, so it won't exist on a brand-new PVC.
    # The version check is skipped in that case; the mismatch will surface at HA load time.
    if [ -f /config/.HA_VERSION ]; then
      target_version=$(sed -n '/^MINIMUM_HA_VERSION/p' /config/custom_components/hacs/const.py | cut -d '"' -f 2)
      [ -n "$target_version" ] || { echo "ERROR: could not parse MINIMUM_HA_VERSION from hacs/const.py" >&2; exit 1; }
      current_version=$(cat /config/.HA_VERSION)

      if [ "$(printf '%s\n%s\n' "${target_version}" "${current_version}" | sort -V | tail -1)" != "${current_version}" ]; then
        rm -rf /config/custom_components/hacs
        echo "ERROR: Home Assistant ${current_version} is too old, HACS requires at least ${target_version}" >&2
        exit 1
      fi
    fi
  fi
fi

if [ "${SECRETS_ENABLED}" = "true" ]; then
  printf '' > /config/secrets.yaml
  for f in "${SECRETS_DIR}"/*; do
    [ -f "$f" ] || continue
    # Use block scalar (|-) so that quotes, backslashes, and newlines in values
    # never produce invalid YAML. Trailing newlines are stripped by the |- chomping.
    printf '%s: |-\n' "$(basename "$f")" >> /config/secrets.yaml
    sed 's/^/  /' "$f" >> /config/secrets.yaml
    printf '\n' >> /config/secrets.yaml
  done
fi

