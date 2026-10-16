#!/usr/bin/env python3
"""Describe un perfil de aprovisionamiento ya decodificado (plist).

Uso: profile_info.py profile.plist etiqueta
Imprime en stdout el número de dispositivos y en stderr un resumen.
Sale con 0 solo si el perfil es Ad Hoc.
"""

import plistlib
import sys


def main() -> int:
    path, label = sys.argv[1], sys.argv[2]
    with open(path, "rb") as fh:
        profile = plistlib.load(fh)
    devices = profile.get("ProvisionedDevices") or []
    entitlements = profile.get("Entitlements") or {}
    get_task_allow = bool(entitlements.get("get-task-allow", False))
    if profile.get("ProvisionsAllDevices"):
        kind = "enterprise"
    elif devices and get_task_allow:
        kind = "development"
    elif devices:
        kind = "ad-hoc"
    else:
        kind = "app-store"
    print(
        f"{label}: perfil «{profile.get('Name')}» · tipo {kind} · "
        f"{len(devices)} dispositivo(s) · expira {profile.get('ExpirationDate')}",
        file=sys.stderr,
    )
    print(len(devices))
    return 0 if kind == "ad-hoc" else 3


if __name__ == "__main__":
    sys.exit(main())
