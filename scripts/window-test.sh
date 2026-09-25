#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
swiftc -parse-as-library -D IMAGE_EDITOR_WINDOW_TEST -module-cache-path "$PWD/.build/module-cache" \
    Sources/ImageEditor/*.swift scripts/window-smoke.swift -o .build/ImageEditorWindowSmoke
.build/ImageEditorWindowSmoke "$@"
