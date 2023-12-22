#!/bin/bash

git clone https://github.com/XargonWan/RetroDECK --depth=1 RetroDECK

# Creating MAME manifest
manifest_header="manifest-header.yml"
mame_module="mame-module.yml"
mame_manifest="net.retrodeck.mame"

sed -n '/cleanup/q;p' RetroDECK/net.retrodeck.retrodeck.yml > "$manifest_header"
sed -i '/^[[:space:]]*#/d' "$manifest_header"
sed -i 's/[[:space:]]*#.*$//' "$manifest_header"

sed -i 's/net.retrodeck.retrodeck/net.retrodeck.mame/' "$manifest_header"
sed -i 's/retrodeck\.sh/mame/' "$manifest_header"

cat "$manifest_header" > "$mame_manifest"
cat "$mame_module" >> "$mame_manifest"

rm -rf RetroDECK