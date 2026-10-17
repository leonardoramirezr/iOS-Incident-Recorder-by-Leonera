#!/usr/bin/env python3
"""Utilidades para la API de App Store Connect usadas por el workflow.

Solo usa la biblioteca estándar de Python y `openssl` (para firmar el JWT ES256).

Variables de entorno: ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_PATH (ruta al .p8) o
ASC_KEY_P8 (contenido del .p8).

Subcomandos:
  write-key --output PATH      Escribe el .p8 (acepta PEM, PEM con "\\n" literales o base64).
  check                        Comprueba que la clave funciona y que hay ≥1 iPhone/iPad registrado.
  keychain-serials             Lista los seriales de los certificados "Apple Development" del llavero.
  revoke-new-dev-certs --before FILE
                               Revoca por la API los certificados de desarrollo que aparecieron
                               en el llavero desde que se guardó FILE (los que creó xcodebuild).
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.appstoreconnect.apple.com"
DEV_CERT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}
PEM_RE = re.compile(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", re.S)


class ASCError(Exception):
    pass


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


# --------------------------------------------------------------------------- JWT


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, index: int) -> tuple[int, int]:
    first = data[index]
    index += 1
    if first < 0x80:
        return first, index
    count = first & 0x7F
    value = int.from_bytes(data[index : index + count], "big")
    return value, index + count


def der_to_raw_signature(der: bytes, size: int = 32) -> bytes:
    """Convierte una firma ECDSA DER (SEQUENCE{INTEGER r, INTEGER s}) a r||s (formato JWS)."""
    if not der or der[0] != 0x30:
        raise ASCError("Firma ECDSA inesperada (no es una secuencia DER)")
    _, index = _read_der_length(der, 1)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ASCError("Firma ECDSA inesperada (falta un INTEGER)")
        length, index = _read_der_length(der, index + 1)
        value = der[index : index + length].lstrip(b"\x00")
        index += length
        if len(value) > size:
            raise ASCError("Firma ECDSA demasiado larga")
        parts.append(value.rjust(size, b"\x00"))
    return parts[0] + parts[1]


def make_jwt(key_id: str, issuer_id: str, key_path: str, lifetime: int = 15 * 60) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + lifetime, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ASCError(
            "openssl no pudo firmar el JWT. ¿ASC_KEY_P8 contiene la clave .p8 completa?\n"
            + result.stderr.decode(errors="replace")
        )
    return signing_input + "." + b64url(der_to_raw_signature(result.stdout))


# --------------------------------------------------------------------------- Clave


def normalize_p8(raw: str) -> str:
    """Acepta el .p8 tal cual, con "\\n" escapados o codificado en base64."""
    text = raw.strip()
    if "\\n" in text and "\n" not in text:
        text = text.replace("\\n", "\n")
    if "-----BEGIN" in text:
        return text.strip() + "\n"
    try:
        decoded = base64.b64decode(text, validate=False)
    except (binascii.Error, ValueError) as exc:
        raise ASCError("ASC_KEY_P8 no es un .p8 válido (ni PEM ni base64)") from exc
    try:
        decoded_text = decoded.decode("utf-8")
    except UnicodeDecodeError:
        decoded_text = ""
    if "-----BEGIN" in decoded_text:
        return decoded_text.strip() + "\n"
    if decoded:
        body = base64.b64encode(decoded).decode("ascii")
        lines = "\n".join(body[i : i + 64] for i in range(0, len(body), 64))
        return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"
    raise ASCError("ASC_KEY_P8 está vacío")


def key_path_from_env() -> str:
    path = os.environ.get("ASC_KEY_PATH")
    if path and os.path.isfile(path):
        return path
    raw = os.environ.get("ASC_KEY_P8")
    if not raw:
        raise ASCError("Falta ASC_KEY_PATH o ASC_KEY_P8")
    handle, temp_path = tempfile.mkstemp(suffix=".p8")
    with os.fdopen(handle, "w") as fh:
        fh.write(normalize_p8(raw))
    os.chmod(temp_path, 0o600)
    return temp_path


def credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer_id = os.environ.get("ASC_ISSUER_ID", "").strip()
    if not key_id or not issuer_id:
        raise ASCError("Faltan ASC_KEY_ID o ASC_ISSUER_ID")
    return key_id, issuer_id, key_path_from_env()


# --------------------------------------------------------------------------- HTTP


class Client:
    def __init__(self) -> None:
        self.key_id, self.issuer_id, self.key_path = credentials()
        self._token: str | None = None
        self._token_time = 0.0

    def token(self) -> str:
        if not self._token or time.time() - self._token_time > 10 * 60:
            self._token = make_jwt(self.key_id, self.issuer_id, self.key_path)
            self._token_time = time.time()
        return self._token

    def request(self, method: str, path_or_url: str, params: dict | None = None) -> dict | None:
        url = path_or_url if path_or_url.startswith("http") else API_BASE + path_or_url
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, method=method)
        request.add_header("Authorization", f"Bearer {self.token()}")
        request.add_header("Accept", "application/json")
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    body = response.read()
                    return json.loads(body) if body else None
            except urllib.error.HTTPError as exc:
                body = exc.read().decode(errors="replace")
                if exc.code in (429, 500, 502, 503, 504) and attempt < 3:
                    time.sleep(2 ** (attempt + 1))
                    continue
                raise ASCError(f"{method} {url} → HTTP {exc.code}\n{describe_errors(body)}") from exc
            except urllib.error.URLError as exc:
                if attempt < 3:
                    time.sleep(2 ** (attempt + 1))
                    continue
                raise ASCError(f"{method} {url} → {exc.reason}") from exc
        return None

    def paginate(self, path: str, params: dict | None = None) -> list[dict]:
        items: list[dict] = []
        payload = self.request("GET", path, params)
        while payload:
            items.extend(payload.get("data", []))
            next_url = (payload.get("links") or {}).get("next")
            payload = self.request("GET", next_url) if next_url else None
        return items


def describe_errors(body: str) -> str:
    try:
        errors = json.loads(body).get("errors", [])
    except (ValueError, AttributeError):
        return body
    return "\n".join(f"  - {e.get('status')} {e.get('code')}: {e.get('title')} — {e.get('detail')}" for e in errors) or body


# --------------------------------------------------------------------------- Certificados


def normalize_serial(value: str) -> str:
    cleaned = value.strip().upper().replace(":", "")
    if cleaned.startswith("SERIAL="):
        cleaned = cleaned[len("SERIAL=") :]
    return cleaned.lstrip("0") or "0"


def keychain_serials(name: str = "Apple Development") -> set[str]:
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", name, "-p"],
        capture_output=True,
        text=True,
        check=False,
    )
    serials: set[str] = set()
    for block in PEM_RE.findall(result.stdout):
        out = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"],
            input=block,
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode == 0 and "=" in out.stdout:
            serials.add(normalize_serial(out.stdout.split("=", 1)[1]))
    return serials


# --------------------------------------------------------------------------- Comandos


def cmd_write_key(args: argparse.Namespace) -> int:
    raw = os.environ.get("ASC_KEY_P8", "")
    if not raw.strip():
        raise ASCError("ASC_KEY_P8 está vacío")
    with open(args.output, "w") as fh:
        fh.write(normalize_p8(raw))
    os.chmod(args.output, 0o600)
    check = subprocess.run(["openssl", "pkey", "-in", args.output, "-noout"], capture_output=True, text=True)
    if check.returncode != 0:
        raise ASCError("El contenido de ASC_KEY_P8 no es una clave privada válida:\n" + check.stderr)
    print(f"Clave escrita en {args.output}")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    client = Client()
    devices = client.paginate(
        "/v1/devices",
        {"filter[platform]": "IOS", "filter[status]": "ENABLED", "limit": "200"},
    )
    print("✅ La clave de App Store Connect funciona.")
    if not devices:
        raise ASCError(
            "No hay dispositivos iOS habilitados en el portal de Apple Developer. "
            "Registra el UDID del iPhone en Certificates, Identifiers & Profiles › Devices."
        )
    print(f"✅ {len(devices)} dispositivo(s) iOS registrado(s):")
    for device in devices:
        attrs = device.get("attributes", {})
        print(f"   • {attrs.get('name')} ({attrs.get('deviceClass')}, {attrs.get('model') or 's/modelo'})")
    if args.github_output:
        with open(args.github_output, "a") as fh:
            fh.write(f"registered_devices={len(devices)}\n")
    return 0


def cmd_keychain_serials(args: argparse.Namespace) -> int:
    for serial in sorted(keychain_serials(args.name)):
        print(serial)
    return 0


def cmd_revoke_new_dev_certs(args: argparse.Namespace) -> int:
    if not os.path.isfile(args.before):
        print("No existe la lista previa de certificados; no se revoca nada.")
        return 0
    with open(args.before) as fh:
        before = {normalize_serial(line) for line in fh if line.strip()}
    new_serials = keychain_serials(args.name) - before
    if not new_serials:
        print("xcodebuild no creó certificados de desarrollo nuevos; nada que revocar.")
        return 0
    print(f"Certificados nuevos en el llavero: {', '.join(sorted(new_serials))}")

    client = Client()
    certificates = client.paginate("/v1/certificates", {"limit": "200"})
    revoked = 0
    for cert in certificates:
        attrs = cert.get("attributes", {})
        serial = normalize_serial(attrs.get("serialNumber") or "")
        if serial in new_serials and attrs.get("certificateType") in DEV_CERT_TYPES:
            client.request("DELETE", f"/v1/certificates/{cert['id']}")
            revoked += 1
            print(f"🗑️  Revocado {attrs.get('name') or attrs.get('displayName')} ({serial})")
    missing = len(new_serials) - revoked
    if missing:
        print(f"⚠️  {missing} certificado(s) nuevo(s) no se encontraron en App Store Connect.")
    print(f"Revocados: {revoked}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("write-key", help="escribe el .p8 desde ASC_KEY_P8")
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_write_key)

    p = sub.add_parser("check", help="valida la clave y los dispositivos registrados")
    p.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT"))
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("keychain-serials", help="seriales de certificados de desarrollo en el llavero")
    p.add_argument("--name", default="Apple Development")
    p.set_defaults(func=cmd_keychain_serials)

    p = sub.add_parser("revoke-new-dev-certs", help="revoca los certificados de desarrollo nuevos")
    p.add_argument("--before", required=True)
    p.add_argument("--name", default="Apple Development")
    p.set_defaults(func=cmd_revoke_new_dev_certs)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ASCError as exc:
        eprint(f"::error::{exc}".replace("\n", "%0A"))
        return 1


if __name__ == "__main__":
    sys.exit(main())
