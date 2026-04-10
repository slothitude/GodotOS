#!/usr/bin/env bash
## Configure godotcode submodule to exclude its project.godot
## Godot won't preload scripts across project boundaries,
## so the submodule's project.godot must be excluded via sparse-checkout.
##
## Run once after cloning: git submodule update --init && bash setup_submodule.sh

set -e

SUBMODULE_DIR="addons/godotcode"
GITDIR=".git/modules/addons/godotcode"

if [ ! -d "$GITDIR" ]; then
    echo "Error: submodule not initialized. Run: git submodule update --init"
    exit 1
fi

# Enable sparse-checkout and exclude project.godot
git -C "$GITDIR" config core.sparseCheckout true
mkdir -p "$GITDIR/info"
printf '/*\n!project.godot\n' > "$GITDIR/info/sparse-checkout"

# Re-apply checkout to remove project.godot
cd "$SUBMODULE_DIR"
git read-tree -mu HEAD
cd ..

# Verify
if [ -f "$SUBMODULE_DIR/project.godot" ]; then
    echo "Warning: project.godot still present — sparse-checkout may not have applied"
    exit 1
fi

echo "OK: submodule configured (project.godot excluded via sparse-checkout)"
