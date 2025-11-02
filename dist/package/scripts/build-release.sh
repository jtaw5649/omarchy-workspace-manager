#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
WORK_DIR="$DIST_DIR/package"

rm -rf "$DIST_DIR"
mkdir -p "$WORK_DIR"

if [[ "${OWM_SKIP_CHECKS:-0}" != "1" ]]; then
	echo "[build-release] running lint"
	scripts/lint.sh
fi

if [[ -f "$PROJECT_ROOT/version" ]]; then
	VERSION="$(<"$PROJECT_ROOT/version")"
elif [[ -f "$PROJECT_ROOT/VERSION" ]]; then
	VERSION="$(<"$PROJECT_ROOT/VERSION")"
else
	VERSION="$(git -C "$PROJECT_ROOT" describe --tags --dirty 2>/dev/null || echo dev)"
fi

TARBALL="omarchy-workspace-manager-${VERSION}.tar.gz"

mkdir -p "$WORK_DIR/bin" "$WORK_DIR/lib" "$WORK_DIR/config" "$WORK_DIR/docs" "$WORK_DIR/install" "$WORK_DIR/scripts"

cp "$PROJECT_ROOT/bin/omarchy-workspace-manager" "$WORK_DIR/bin/"
cp -R "$PROJECT_ROOT/lib/." "$WORK_DIR/lib/"
cp -R "$PROJECT_ROOT/config/." "$WORK_DIR/config/"
cp "$PROJECT_ROOT/install.sh" "$WORK_DIR/"
cp -R "$PROJECT_ROOT/install/." "$WORK_DIR/install/"
cp -R "$PROJECT_ROOT/scripts/." "$WORK_DIR/scripts/"
cp "$PROJECT_ROOT/README.md" "$WORK_DIR/"
cp "$PROJECT_ROOT/version" "$WORK_DIR/" 2>/dev/null || true

chmod +x "$WORK_DIR/bin/omarchy-workspace-manager"
find "$WORK_DIR/lib" -type f -name '*.sh' -exec chmod +x {} +
find "$WORK_DIR/install" -type f -name '*.sh' -exec chmod +x {} +
find "$WORK_DIR/scripts" -type f -name '*.sh' -exec chmod +x {} +

mkdir -p "$DIST_DIR"
(cd "$WORK_DIR" && tar -czf "$DIST_DIR/$TARBALL" .)

echo "Created dist/$TARBALL"
