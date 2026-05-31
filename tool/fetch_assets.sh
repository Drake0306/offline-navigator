#!/usr/bin/env bash
# Fetch offline glyph fonts (PBF ranges) for the MapLibre style.
# Source: protomaps/basemaps-assets (prebuilt PBF glyph ranges).
set -euo pipefail

TMP="$(mktemp -d)"
echo "Cloning basemaps-assets into $TMP ..."
git clone --depth 1 https://github.com/protomaps/basemaps-assets "$TMP/assets"

echo "Available font stacks:"
ls "$TMP/assets/fonts"

# Copy the Noto Sans Regular stack if present (adjust name per the ls output above).
STACK="Noto Sans Regular"
mkdir -p "assets/glyphs/$STACK"
cp "$TMP/assets/fonts/$STACK/"*.pbf "assets/glyphs/$STACK/"
echo "Copied $(ls assets/glyphs/"$STACK" | wc -l) range files into assets/glyphs/$STACK"
rm -rf "$TMP"
