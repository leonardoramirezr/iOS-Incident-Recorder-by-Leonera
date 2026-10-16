#!/usr/bin/env bash
# Verifica que cada bundle (.app y .appex) del IPA lleva un embedded.mobileprovision
# Ad Hoc y muestra cuántos dispositivos incluye.
# Uso: scripts/verify-adhoc.sh ruta/al.ipa
# Escribe `devices=<n>` en $GITHUB_OUTPUT si existe.
set -euo pipefail

IPA="${1:?uso: verify-adhoc.sh ruta/al.ipa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unzip -q "$IPA" -d "$WORK/ipa"

status=0
min_devices=""
found=0
while IFS= read -r -d '' bundle; do
  found=$((found + 1))
  rel="${bundle#"$WORK/ipa/"}"
  profile="$bundle/embedded.mobileprovision"
  if [ ! -f "$profile" ]; then
    echo "::error::$rel no contiene embedded.mobileprovision"
    status=1
    continue
  fi
  security cms -D -i "$profile" -o "$WORK/profile.plist"
  if ! result="$(python3 "$SCRIPT_DIR/profile_info.py" "$WORK/profile.plist" "$rel")"; then
    echo "::error::$rel no está firmado con un perfil Ad Hoc"
    status=1
    continue
  fi
  if [ -z "$min_devices" ] || [ "$result" -lt "$min_devices" ]; then
    min_devices="$result"
  fi
done < <(find "$WORK/ipa/Payload" \( -name '*.app' -o -name '*.appex' \) -type d -print0)

if [ "$found" -eq 0 ]; then
  echo "::error::El IPA no contiene bundles en Payload/"
  exit 1
fi
if [ "$status" -ne 0 ]; then
  exit "$status"
fi

echo "✅ $found bundle(s) con perfil Ad Hoc; el perfil incluye ${min_devices} dispositivo(s)."
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "devices=${min_devices}" >> "$GITHUB_OUTPUT"
fi
