#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="$VERSION" BUILD="${BUILD:-1}" scripts/build-app.sh
rm -f build/Sophia.zip build/Sophia.zip.sha256
ditto -c -k --keepParent build/Sophia.app build/Sophia.zip
(cd build && shasum -a 256 Sophia.zip > Sophia.zip.sha256)
echo "build/Sophia.zip and build/Sophia.zip.sha256 ready for release v$VERSION"
cat build/Sophia.zip.sha256
