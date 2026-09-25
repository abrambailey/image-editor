#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
open "dist/Image Editor.app"
