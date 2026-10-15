#!/bin/sh
# Builds the Forge package, pkg/eyalsec-es_python-<version>.tar.gz, from this checkout.
set -eu
cd "$(dirname "$0")/.."
v="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' metadata.json | head -n 1)"
name="eyalsec-es_python-$v"
rm -rf pkg && mkdir -p "pkg/$name"
cp -R metadata.json README.md LICENSE CHANGELOG.md manifests files examples "pkg/$name/"
tar -C pkg -czf "pkg/$name.tar.gz" "$name"
rm -rf "pkg/$name"
echo "pkg/$name.tar.gz"
