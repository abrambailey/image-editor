#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export IMAGE_EDITOR_MODEL_PATH="${IMAGE_EDITOR_MODEL_PATH:-$PWD/.build/models/BiRefNetLite.mlmodelc}"
swiftc -O -parse-as-library -module-cache-path "$PWD/.build/module-cache" \
    Sources/ImageEditor/ForegroundExtractor.swift \
    Sources/ImageEditor/ImageEngine.swift \
    Sources/ImageEditor/EditorModel.swift Sources/ImageEditor/EditorWorkspace.swift \
    Sources/ImageEditor/SunburstClient.swift Sources/ImageEditor/AIEditImaging.swift Sources/ImageEditor/AIEditSession.swift \
    Tests/ImageEditorTests/*.swift \
    -o .build/ImageEditorTests
.build/ImageEditorTests "$@"
