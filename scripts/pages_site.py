#!/usr/bin/env python3
"""Genera el contenido de GitHub Pages para instalar los builds Ad Hoc.

  add-build   Crea <site>/<tag>/ con el IPA, manifest.plist, index.html, build.json e iconos.
  finalize    Conserva todos los builds de main y los últimos N de otras ramas, y
              regenera la portada (index.html) con la lista de builds.

Solo biblioteca estándar.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import plistlib
import shutil
import sys
import urllib.parse
from datetime import datetime, timezone

IPA_NAME = "IncidentRecorder.ipa"

STYLE = """
:root { color-scheme: light dark; --bg:#0b0d10; --card:#161a20; --text:#f2f4f7; --muted:#9aa4b2; --accent:#e53935; --line:#262c35; }
@media (prefers-color-scheme: light) { :root { --bg:#f5f6f8; --card:#ffffff; --text:#14171c; --muted:#5d6774; --line:#e3e6ea; } }
* { box-sizing: border-box; }
body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background:var(--bg); color:var(--text); }
main { max-width:720px; margin:0 auto; padding:24px 16px 48px; }
header { display:flex; align-items:center; gap:16px; margin-bottom:24px; }
header img { width:72px; height:72px; border-radius:16px; }
h1 { font-size:1.5rem; margin:0; }
h2 { font-size:1.1rem; margin:32px 0 12px; }
p, li { line-height:1.5; }
.muted { color:var(--muted); font-size:.9rem; }
.card { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; margin-bottom:12px; }
.button { display:block; text-align:center; background:var(--accent); color:#fff; text-decoration:none; font-weight:600; padding:14px 18px; border-radius:12px; font-size:1.05rem; }
.button.secondary { background:transparent; color:var(--accent); border:1px solid var(--accent); }
.row { display:flex; justify-content:space-between; align-items:center; gap:12px; }
.badge { font-size:.75rem; font-weight:700; padding:2px 8px; border-radius:999px; background:var(--line); }
.badge.stable { background:#1b5e20; color:#fff; }
.badge.pre { background:#8d5a00; color:#fff; }
a { color:var(--accent); }
code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.85rem; }
ol { padding-left:20px; }
"""


def itms_link(manifest_url: str) -> str:
    return "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")


def page(title: str, body: str) -> str:
    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{STYLE}</style>
</head>
<body><main>
{body}
</main></body>
</html>
"""


def install_help() -> str:
    return """
<h2>Cómo instalar</h2>
<ol>
  <li>Abre esta página en <strong>Safari</strong> en el iPhone (registrado en la cuenta de Apple Developer).</li>
  <li>Toca <strong>Instalar</strong> y confirma.</li>
  <li>Si iOS lo pide, activa <strong>Ajustes › Privacidad y seguridad › Modo de desarrollador</strong>.</li>
</ol>
<p class="muted">Si el iPhone no está registrado la instalación falla: registra su UDID en el portal de Apple Developer y vuelve a hacer push para generar un build que lo incluya.</p>
"""


def cmd_add_build(args: argparse.Namespace) -> int:
    base_url = args.base_url.rstrip("/") + "/"
    folder = os.path.join(args.site, args.tag)
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)

    shutil.copy2(args.ipa, os.path.join(folder, IPA_NAME))
    shutil.copy2(args.icon_57, os.path.join(folder, "icon-57.png"))
    shutil.copy2(args.icon_512, os.path.join(folder, "icon-512.png"))

    build_url = base_url + urllib.parse.quote(args.tag) + "/"
    manifest_url = build_url + "manifest.plist"
    manifest = {
        "items": [
            {
                "assets": [
                    {"kind": "software-package", "url": build_url + IPA_NAME},
                    {"kind": "display-image", "url": build_url + "icon-57.png"},
                    {"kind": "full-size-image", "url": build_url + "icon-512.png"},
                ],
                "metadata": {
                    "bundle-identifier": args.bundle_id,
                    "bundle-version": args.version,
                    "kind": "software",
                    "title": args.app_name,
                },
            }
        ]
    }
    with open(os.path.join(folder, "manifest.plist"), "wb") as fh:
        plistlib.dump(manifest, fh)

    published_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    info = {
        "tag": args.tag,
        "kind": args.kind,
        "version": args.version,
        "build_number": args.build_number,
        "branch": args.branch,
        "commit": args.commit,
        "run_number": int(args.run_number),
        "run_url": args.run_url,
        "devices": int(args.devices) if str(args.devices).isdigit() else None,
        "bundle_id": args.bundle_id,
        "published_at": published_at,
        "ipa": IPA_NAME,
        "page_url": build_url,
        "manifest_url": manifest_url,
        "install_url": itms_link(manifest_url),
    }
    with open(os.path.join(folder, "build.json"), "w") as fh:
        json.dump(info, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    kind_label = "Estable" if args.kind == "stable" else "Pre-release"
    devices = f"{info['devices']} dispositivo(s) en el perfil Ad Hoc" if info["devices"] is not None else ""
    body = f"""
<header>
  <img src="icon-512.png" alt="">
  <div>
    <h1>{html.escape(args.app_name)}</h1>
    <div class="muted">{html.escape(args.version)} ({html.escape(str(args.build_number))}) · <span class="badge {'stable' if args.kind == 'stable' else 'pre'}">{kind_label}</span></div>
  </div>
</header>
<a class="button" href="{html.escape(info['install_url'])}">Instalar {html.escape(args.tag)}</a>
<div class="card" style="margin-top:16px">
  <div class="row"><span class="muted">Etiqueta</span><code>{html.escape(args.tag)}</code></div>
  <div class="row"><span class="muted">Rama</span><code>{html.escape(args.branch)}</code></div>
  <div class="row"><span class="muted">Commit</span><code>{html.escape(args.commit[:7])}</code></div>
  <div class="row"><span class="muted">Publicado</span><span>{html.escape(published_at)}</span></div>
  <div class="row"><span class="muted">Perfil</span><span>{html.escape(devices)}</span></div>
</div>
<p><a href="{IPA_NAME}">Descargar el IPA</a> · <a href="../">Todos los builds</a> · <a href="{html.escape(args.run_url)}">Ejecución en GitHub Actions</a></p>
{install_help()}
"""
    with open(os.path.join(folder, "index.html"), "w") as fh:
        fh.write(page(f"{args.app_name} {args.tag}", body))
    print(f"Build {args.tag} agregado en {folder}")
    return 0


def load_builds(site: str) -> list[dict]:
    builds = []
    for name in sorted(os.listdir(site)):
        path = os.path.join(site, name, "build.json")
        if os.path.isfile(path):
            try:
                with open(path) as fh:
                    data = json.load(fh)
                data["_folder"] = name
                builds.append(data)
            except (OSError, ValueError):
                continue
    return builds


def version_key(version: str) -> tuple:
    parts = []
    for part in str(version).split("."):
        parts.append(int(part) if part.isdigit() else 0)
    return tuple(parts)


def sort_key(build: dict) -> tuple:
    return (build.get("published_at") or "", build.get("run_number") or 0)


def cmd_finalize(args: argparse.Namespace) -> int:
    builds = load_builds(args.site)
    stable = [b for b in builds if b.get("kind") == "stable"]
    others = sorted((b for b in builds if b.get("kind") != "stable"), key=sort_key, reverse=True)
    for old in others[args.keep_branch_builds :]:
        shutil.rmtree(os.path.join(args.site, old["_folder"]), ignore_errors=True)
        print(f"Eliminado build antiguo de rama: {old['_folder']}")
    kept = stable + others[: args.keep_branch_builds]
    kept.sort(key=sort_key, reverse=True)

    latest_stable = max(stable, key=lambda b: version_key(b.get("version", "0"))) if stable else None
    if latest_stable:
        hero = f"""
<a class="button" href="{html.escape(latest_stable['install_url'])}">Instalar la última versión estable ({html.escape(latest_stable['version'])})</a>
<p class="muted" style="text-align:center"><a href="{html.escape(latest_stable['_folder'])}/">Detalles de {html.escape(latest_stable['tag'])}</a></p>
"""
    else:
        hero = '<div class="card">Todavía no hay una versión estable (se publica al hacer push a <code>main</code>).</div>'

    rows = []
    for build in kept:
        badge = '<span class="badge stable">Estable</span>' if build.get("kind") == "stable" else '<span class="badge pre">Pre-release</span>'
        rows.append(
            f"""<div class="card">
  <div class="row"><strong><a href="{html.escape(build['_folder'])}/">{html.escape(build['tag'])}</a></strong>{badge}</div>
  <div class="muted">{html.escape(build.get('version', ''))} · rama <code>{html.escape(build.get('branch', ''))}</code> · <code>{html.escape((build.get('commit') or '')[:7])}</code> · {html.escape(build.get('published_at', ''))}</div>
  <p style="margin:10px 0 0"><a class="button secondary" href="{html.escape(build['install_url'])}">Instalar</a></p>
</div>"""
        )
    icon = f'<img src="{html.escape(latest_stable["_folder"])}/icon-512.png" alt="">' if latest_stable else (
        f'<img src="{html.escape(kept[0]["_folder"])}/icon-512.png" alt="">' if kept else ""
    )
    body = f"""
<header>
  {icon}
  <div>
    <h1>{html.escape(args.app_name)}</h1>
    <div class="muted">Builds Ad Hoc para instalar desde Safari</div>
  </div>
</header>
{hero}
{install_help()}
<h2>Todos los builds</h2>
{''.join(rows) if rows else '<p class="muted">Sin builds.</p>'}
"""
    with open(os.path.join(args.site, "index.html"), "w") as fh:
        fh.write(page(args.app_name, body))
    open(os.path.join(args.site, ".nojekyll"), "w").close()
    print(f"Portada generada con {len(kept)} build(s).")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("add-build")
    p.add_argument("--site", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--kind", choices=["stable", "prerelease"], required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build-number", required=True)
    p.add_argument("--branch", required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--run-number", required=True)
    p.add_argument("--run-url", required=True)
    p.add_argument("--devices", default="")
    p.add_argument("--ipa", required=True)
    p.add_argument("--icon-57", required=True)
    p.add_argument("--icon-512", required=True)
    p.add_argument("--base-url", required=True)
    p.add_argument("--app-name", required=True)
    p.add_argument("--bundle-id", required=True)
    p.set_defaults(func=cmd_add_build)

    p = sub.add_parser("finalize")
    p.add_argument("--site", required=True)
    p.add_argument("--app-name", required=True)
    p.add_argument("--keep-branch-builds", type=int, default=20)
    p.set_defaults(func=cmd_finalize)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
