#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Pin both the repository revision and the archive digest. No Python runtime,
# source checkout, or model download is needed by the finished app.
revision=519543b900332b0fd834ab7a40a17099b2d2e7cb
digest=46e7f3306069d1385761c0db86d65913dc3f980bf5348eb0c3db429e3f8414b7
model_dir="$PWD/.build/models"
archive="$model_dir/BiRefNetLite.zip"
package="$model_dir/BiRefNetLite-1024-FP16Compute-FP32IO.mlpackage"
compiled="$model_dir/BiRefNetLite.mlmodelc"
mkdir -p "$model_dir" "$PWD/.build/module-cache"
if [[ -d "$compiled" && -f "$model_dir/revision" && "$(<"$model_dir/revision")" == "$revision" ]]; then
    exit 0
fi
if [[ ! -f "$archive" ]]; then
    echo "Downloading the local background model (82 MB, first build only)…"
    curl --fail --location --retry 2 --connect-timeout 30 --max-time 300 \
        "https://huggingface.co/metaclass/birefnet-lite-coreml/resolve/$revision/fp16compute-fp32io/r1/BiRefNetLite-1024-FP16Compute-FP32IO-iOS17-r1.mlpackage.zip?download=true" \
        --output "$archive.download"
    mv "$archive.download" "$archive"
fi
if [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$digest" ]]; then
    echo "Model checksum failed. Remove $archive and rebuild." >&2
    exit 1
fi
unzip -qo "$archive" 'BiRefNetLite-1024-FP16Compute-FP32IO.mlpackage/*' -d "$model_dir"
rm -rf "$model_dir/BiRefNetLite.pending.mlmodelc"
swift -module-cache-path "$PWD/.build/module-cache" scripts/compile-model.swift \
    "$package" "$model_dir/BiRefNetLite.pending.mlmodelc"
rm -rf "$compiled"
mv "$model_dir/BiRefNetLite.pending.mlmodelc" "$compiled"
print -r -- "$revision" > "$model_dir/revision"
