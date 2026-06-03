#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_CODEX_TO_IM_ROOT="$(cd "$SITE_ROOT/.." && pwd)/codex-to-im"

CODEX_TO_IM_ROOT="${CODEX_TO_IM_ROOT:-$DEFAULT_CODEX_TO_IM_ROOT}"
SOURCE_DIR="${CODEX_TO_IM_DOCS_DIST:-$CODEX_TO_IM_ROOT/docs/.vitepress/dist}"
TARGET_PATH="${TARGET_PATH:-sites/codelark}"
BASE_PATH="${BASE_PATH:-/$TARGET_PATH/}"
RUN_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/sync-codex-to-im-docs.sh [--build] [--source DIR] [--target sites/codelark]

Copies the built Codex-to-IM VitePress docs into this GitHub Pages site.

Defaults:
  source: ../codex-to-im/docs/.vitepress/dist
  target: sites/codelark

Options:
  --build       Run npm run docs:build in ../codex-to-im with Node.js 24 first.
  --source DIR  Use a custom built docs directory.
  --target DIR  Use a custom mount directory inside this repository.
  -h, --help    Show this help.

Environment:
  CODEX_TO_IM_ROOT       Path to the codex-to-im repository.
  CODEX_TO_IM_DOCS_DIST  Path to an existing built VitePress dist directory.
  TARGET_PATH            Mount path inside this repository.
  BASE_PATH              Public URL prefix. Defaults to /$TARGET_PATH/.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build)
      RUN_BUILD=1
      shift
      ;;
    --source)
      SOURCE_DIR="${2:?missing value for --source}"
      shift 2
      ;;
    --target)
      TARGET_PATH="${2:?missing value for --target}"
      BASE_PATH="/$TARGET_PATH/"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

TARGET_PATH="${TARGET_PATH#/}"
TARGET_PATH="${TARGET_PATH%/}"
BASE_PATH="${BASE_PATH%/}/"
TARGET_DIR="$SITE_ROOT/$TARGET_PATH"

case "$TARGET_PATH" in
  sites/*) ;;
  *)
    echo "Refusing to sync outside sites/: $TARGET_PATH" >&2
    exit 2
    ;;
esac

if [ "$RUN_BUILD" -eq 1 ]; then
  if [ ! -d "$CODEX_TO_IM_ROOT" ]; then
    echo "Codex-to-IM repository not found: $CODEX_TO_IM_ROOT" >&2
    exit 1
  fi
  (
    cd "$CODEX_TO_IM_ROOT"
    unset NODE_OPTIONS
    # shellcheck disable=SC1090
    source ~/.nvm/nvm.sh
    nvm use 24
    npm run docs:build
  )
fi

if [ ! -f "$SOURCE_DIR/index.html" ]; then
  echo "Built docs not found at $SOURCE_DIR. Run with --build or build Codex-to-IM docs first." >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SOURCE_DIR"/ "$TARGET_DIR"/
else
  cp -a "$SOURCE_DIR"/. "$TARGET_DIR"/
fi

# VitePress was built with base="/". When mounted under /sites/codelark/,
# rewrite absolute asset and navigation paths in the copied static files.
export BASE_PATH
find "$TARGET_DIR" -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' -o -name '*.json' \) -print0 |
  xargs -0 perl -0pi -e '
    my $base = $ENV{BASE_PATH};
    my $base_rel = quotemeta(substr($base, 1));
    s#\b(href|src|content)=(["'"'"'])/#$1=$2$base#g;
    s#url\(/#url($base#g;
    s#(["'"'"'`])/(?!/|$base_rel|[A-Za-z][A-Za-z0-9+.-]*:|\#)#$1$base#g;
    s#\\(["'"'"'`])/(?!/|$base_rel|[A-Za-z][A-Za-z0-9+.-]*:|\#)#\\$1$base#g;
  '

echo "Synced Codex-to-IM docs:"
echo "  source: $SOURCE_DIR"
echo "  target: $TARGET_DIR"
echo "  url:    $BASE_PATH"
