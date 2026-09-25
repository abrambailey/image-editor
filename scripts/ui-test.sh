#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
export IMAGE_EDITOR_MODEL_PATH="${IMAGE_EDITOR_MODEL_PATH:-$PWD/.build/models/BiRefNetLite.mlmodelc}"
swiftc -parse-as-library -module-cache-path "$PWD/.build/module-cache" \
    Sources/ImageEditor/ForegroundExtractor.swift \
    Sources/ImageEditor/ImageEngine.swift Sources/ImageEditor/EditorModel.swift \
    Sources/ImageEditor/CanvasView.swift Sources/ImageEditor/EditorView.swift \
    Sources/ImageEditor/EditorWorkspace.swift Sources/ImageEditor/EditorWorkspaceView.swift \
    Sources/ImageEditor/SunburstClient.swift Sources/ImageEditor/AIEditImaging.swift \
    Sources/ImageEditor/AIEditSession.swift Sources/ImageEditor/AIEditView.swift \
    scripts/ui-smoke.swift -o .build/ImageEditorUISmoke
.build/ImageEditorUISmoke "$@"
