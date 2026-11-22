#!/bin/sh
# Stage a downloaded local MLX model where the evaluation's test runner can
# read it.
#
# The models live in the App Group container
# (~/Library/Group Containers/<group>/SharedModels). macOS refuses an unsigned
# test runner access to another app's group container ("you don't have
# permission"), so the evaluation reads a copy-on-write clone (cp -c: instant,
# no extra disk space on APFS) under .build/eval-models instead, through
# ACERVO_MODELS_DIR. An existing clone is kept.
#
# Usage: stage-bruja-model.sh <model id> <destination dir> <app group id>
set -eu

model_id="$1"
destination="$2"
group="$3"

slug=$(printf '%s' "$model_id" | tr '/' '_')
source_dir="$HOME/Library/Group Containers/$group/SharedModels/$slug"

if [ ! -f "$source_dir/config.json" ]; then
  echo "$model_id isn't downloaded (no $source_dir/config.json). Run: bruja download -m $model_id" >&2
  exit 1
fi

mkdir -p "$destination"
if [ ! -f "$destination/$slug/config.json" ]; then
  cp -cR "$source_dir" "$destination/$slug"
  echo "Staged $model_id in $destination (APFS clone)."
fi
