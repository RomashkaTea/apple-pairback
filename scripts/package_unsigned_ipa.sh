#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
repo_dir="$PWD"
build_dir="${PB_BUILD_DIR:-/tmp/PairBackBuild}"
xcodegen generate
xcodebuild -project PairBack.xcodeproj -scheme PairBack -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

app="$build_dir/Build/Products/Release-iphoneos/PairBack.app"
[[ -d "$app" ]] || { print -u2 'PairBack.app was not produced'; exit 1; }
package_dir=$(mktemp -d /tmp/PairBackPackage.XXXXXX)
mkdir "$package_dir/Payload"
ditto "$app" "$package_dir/Payload/PairBack.app"
mkdir -p dist
(cd "$package_dir" && /usr/bin/zip -qry "$package_dir/PairBack-unsigned.ipa" Payload)
mv "$package_dir/PairBack-unsigned.ipa" "$repo_dir/dist/PairBack-unsigned.ipa"
unzip -tq dist/PairBack-unsigned.ipa
shasum -a 256 dist/PairBack-unsigned.ipa | awk '{ print $1 "  PairBack-unsigned.ipa" }' > dist/SHA256SUMS
cat dist/SHA256SUMS
