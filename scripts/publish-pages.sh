#!/usr/bin/env bash
# Publica un build firmado en la rama gh-pages (GitHub Pages), una carpeta por etiqueta.
#
# - Reescribe gh-pages como un único commit huérfano: los IPA no se acumulan en el historial.
# - Conserva solo las carpetas que tienen build.json (la rama pudo crearse desde el código).
# - Guarda todos los builds de main y los últimos KEEP_BRANCH_BUILDS (20) de otras ramas.
# - Añade .nojekyll y usa `git add -A --force` para que un .gitignore con *.ipa no excluya el IPA.
# - Hace push --force-with-lease y reintenta si otro build publicó al mismo tiempo.
#
# Variables requeridas:
#   TAG KIND(stable|prerelease) VERSION BUILD_NUMBER BRANCH COMMIT RUN_NUMBER RUN_URL
#   IPA_PATH ICON_57 ICON_512 BASE_URL APP_NAME BUNDLE_ID GITHUB_REPOSITORY GH_TOKEN
# Opcionales:
#   DEVICE_COUNT, KEEP_BRANCH_BUILDS (20), PAGES_BRANCH (gh-pages), MAX_ATTEMPTS (6)
#   PAGES_REMOTE (URL del remoto; por defecto https://github.com/$GITHUB_REPOSITORY.git con el token)
set -euo pipefail

for name in TAG KIND VERSION BUILD_NUMBER BRANCH COMMIT RUN_NUMBER RUN_URL IPA_PATH ICON_57 ICON_512 BASE_URL APP_NAME BUNDLE_ID GITHUB_REPOSITORY; do
  if [ -z "${!name:-}" ]; then
    echo "::error::publish-pages.sh: falta la variable $name" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
KEEP_BRANCH_BUILDS="${KEEP_BRANCH_BUILDS:-20}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-6}"
if [ -z "${PAGES_REMOTE:-}" ]; then
  : "${GH_TOKEN:?falta GH_TOKEN}"
  PAGES_REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

attempt=1
while :; do
  echo "▶︎ Publicando $TAG en $PAGES_BRANCH (intento $attempt/$MAX_ATTEMPTS)"
  rm -rf "$WORK/current" "$WORK/site"
  mkdir -p "$WORK/site"

  # 1) Estado actual de la rama (si existe). El lease se hace contra exactamente
  #    el commit que se descargó.
  expected_sha=""
  git init -q "$WORK/current"
  if git -C "$WORK/current" fetch -q --depth 1 "$PAGES_REMOTE" "refs/heads/$PAGES_BRANCH" 2>/dev/null; then
    expected_sha="$(git -C "$WORK/current" rev-parse FETCH_HEAD)"
    git -C "$WORK/current" checkout -q FETCH_HEAD
  fi

  # 2) Conservar solo las carpetas de builds (las que tienen build.json).
  for dir in "$WORK/current"/*/; do
    dir="${dir%/}"
    [ -d "$dir" ] || continue
    if [ -f "$dir/build.json" ]; then
      cp -R "$dir" "$WORK/site/"
    fi
  done

  # 3) Agregar el build nuevo y regenerar la portada.
  python3 "$SCRIPT_DIR/pages_site.py" add-build \
    --site "$WORK/site" \
    --tag "$TAG" \
    --kind "$KIND" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --branch "$BRANCH" \
    --commit "$COMMIT" \
    --run-number "$RUN_NUMBER" \
    --run-url "$RUN_URL" \
    --devices "${DEVICE_COUNT:-}" \
    --ipa "$IPA_PATH" \
    --icon-57 "$ICON_57" \
    --icon-512 "$ICON_512" \
    --base-url "$BASE_URL" \
    --app-name "$APP_NAME" \
    --bundle-id "$BUNDLE_ID"
  python3 "$SCRIPT_DIR/pages_site.py" finalize \
    --site "$WORK/site" \
    --app-name "$APP_NAME" \
    --keep-branch-builds "$KEEP_BRANCH_BUILDS"
  touch "$WORK/site/.nojekyll"

  # 4) Un único commit huérfano.
  git -C "$WORK/site" init -q
  git -C "$WORK/site" checkout -q --orphan "$PAGES_BRANCH"
  git -C "$WORK/site" add -A --force
  git -C "$WORK/site" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -q -m "Publicar $TAG ($VERSION)"

  # 5) Push con lease: falla si otro build cambió la rama mientras tanto.
  if git -C "$WORK/site" push -q --force-with-lease="refs/heads/$PAGES_BRANCH:$expected_sha" \
      "$PAGES_REMOTE" "HEAD:refs/heads/$PAGES_BRANCH"; then
    echo "✅ $TAG publicado en $PAGES_BRANCH"
    break
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "::error::No se pudo publicar en $PAGES_BRANCH tras $MAX_ATTEMPTS intentos" >&2
    exit 1
  fi
  wait_seconds=$((attempt * 10))
  echo "⚠️  Otro build publicó al mismo tiempo; reintento en ${wait_seconds}s"
  sleep "$wait_seconds"
  attempt=$((attempt + 1))
done
