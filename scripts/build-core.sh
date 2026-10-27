#!/bin/sh
# Builds the ShellRS core from a checkout of shell-rs and puts it where the
# ShellRSCore package looks for it: the xcframework and its Swift interface,
# neither of which is committed.
#
#   SHELLRS_DIR  the shell-rs checkout, ../shell-rs unless set
#
# Packages/ShellRSCore/core-revision names the shell-rs commit this app goes
# with. A checkout at another commit, or with changes to its crates, is
# built all the same, with a warning.
#
# Needs what shell-rs's scripts/build-ios.sh needs: Xcode and
# `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`.
set -eu
cd "$(dirname "$0")/.."
package="$PWD/Packages/ShellRSCore"
shellrs=$(cd "${SHELLRS_DIR:-../shell-rs}" && pwd)

revision=$(git -C "$shellrs" rev-parse HEAD)
expected=$(cat "$package/core-revision")
if [ "$revision" != "$expected" ]; then
    echo "warning: shell-rs is at $revision; this app goes with $expected" >&2
fi
if [ -n "$(git -C "$shellrs" status --porcelain -- crates Cargo.lock)" ]; then
    echo "warning: shell-rs has changes not committed" >&2
fi

IPHONEOS_DEPLOYMENT_TARGET=17.0 "$shellrs/scripts/build-ios.sh"

built="$shellrs/target/mobile/ios"
rm -rf "$package/ShellRSCore.xcframework"
cp -R "$built/ShellRSCore.xcframework" "$package/"
cp "$built/Sources/ShellRSCore.swift" "$package/Sources/ShellRSCore/"
echo "The core is in $package"
