#!/bin/sh
set -e

if [ "${HACS_ENABLED}" = "true" ]; then
  URL="https://github.com/hacs/integration/releases/download/${HACS_VERSION}/hacs.zip"
  if [ ! -d /config/custom_components/hacs ]; then
    apk add -q --no-progress unzip
    mkdir -p /config/custom_components/hacs
    wget -q -O /tmp/hacs.zip "$URL"
    unzip -q /tmp/hacs.zip -d /config/custom_components/hacs
    rm /tmp/hacs.zip

    if [ -f /config/.HA_VERSION ]; then
      target_version=$(sed -n '/^MINIMUM_HA_VERSION/p' /config/custom_components/hacs/const.py | cut -d '"' -f 2)
      current_version=$(cat /config/.HA_VERSION)

      target_year=$(echo "${target_version}" | cut -d '.' -f 1)
      target_month=$(echo "${target_version}" | cut -d '.' -f 2)
      target_patch=$(echo "${target_version}" | cut -d '.' -f 3)
      current_year=$(echo "${current_version}" | cut -d '.' -f 1)
      current_month=$(echo "${current_version}" | cut -d '.' -f 2)
      current_patch=$(echo "${current_version}" | cut -d '.' -f 3)

      version_ok=true
      if [ "${current_version}" = "2023.12.0" ]; then
        version_ok=false
      elif [ "${current_year}" -lt "${target_year}" ]; then
        version_ok=false
      elif [ "${current_year}" -eq "${target_year}" ] && [ "${current_month}" -lt "${target_month}" ]; then
        version_ok=false
      elif [ "${current_year}" -eq "${target_year}" ] && [ "${current_month}" -eq "${target_month}" ] && [ "${current_patch}" -lt "${target_patch}" ]; then
        version_ok=false
      fi

      if [ "${version_ok}" = "false" ]; then
        rm -rf /config/custom_components/hacs
        echo "ERROR: Home Assistant ${current_version} is too old, HACS requires at least ${target_version}" >&2
        exit 1
      fi
    fi
  fi
fi

if [ "${SECRETS_ENABLED}" = "true" ]; then
  { set +x; } 2>/dev/null
  printf '' > /config/secrets.yaml
  for f in "${SECRETS_DIR}"/*; do
    [ -f "$f" ] || continue
    value=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$f")
    printf '%s: "%s"\n' "$(basename "$f")" "${value}" >> /config/secrets.yaml
  done
fi

if [ "${CONFIG_ENABLED}" = "true" ]; then
  if [ ! -f /config/configuration.yaml ]; then
    cp /run/ha-bootstrap-config/configuration.yaml /config/configuration.yaml
  fi
fi
