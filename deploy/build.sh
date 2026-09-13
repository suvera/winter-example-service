#!/bin/bash
# Build the example-service PHAR with box (https://github.com/box-project/box).
#   ./deploy/build.sh
# Run from anywhere; paths resolve to the repo root.
set -e
cd "$(dirname "$0")/.."
APP="example-service"
BOX_EXEC="${BOX_EXEC:-box}"

if [ ! -d vendor ]; then
  echo "[$APP] composer install (prod)..."
  composer install --no-interaction --no-dev --optimize-autoloader
fi

echo "[$APP] staging phar sources (dereferences vendor symlinks)..."
# Stage on a Linux-native filesystem (default /tmp, i.e. ext4 in WSL2):
# this repo usually lives on a 9P mount (/mnt/d, /mnt/c) where every file
# costs several slow host round-trips. deploy/stage stays a symlink so
# box.json (base-path: stage) and the steps below work unchanged.
# Override with STAGE_DIR=/path/to/stage to stage elsewhere.
: "${STAGE_DIR:=/tmp/example-service-stage}"
rm -rf deploy/stage "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ln -s "$STAGE_DIR" deploy/stage
cp -r bin src composer.json composer.lock deploy/stage/
# Dereference the path-repo symlinks (e.g. vendor/suvera/winter-boot)
# so the phar is self-contained.
mkdir -p deploy/stage/vendor
if command -v rsync >/dev/null 2>&1; then
  rsync -aL vendor/ deploy/stage/vendor/
else
  cp -rL vendor/ deploy/stage/vendor/
fi

echo "[$APP] box compile..."
(cd deploy && "$BOX_EXEC" compile)

# Box resolves "output" against the canonical (symlink-free) stage path,
# so with the default /tmp STAGE_DIR the phar lands in /tmp/target/, not
# ./target/. Move it back to the repo target dir.
PHAR="$(dirname "$(readlink -f deploy/stage)")/target/example-service.phar"
mkdir -p target
if [ "$PHAR" != "$(pwd)/target/example-service.phar" ]; then
  mv -f "$PHAR" target/example-service.phar
fi

echo "[$APP] done: target/example-service.phar"
