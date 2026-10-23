#!/bin/bash
set -euo pipefail
# The pinned release uses build/utils.sh (not build_utils.sh in newer docs).
export EXPANDED_CODE_SIGN_IDENTITY="-"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="Ad Hoc"
source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"
install_python Vendor/Python.xcframework
