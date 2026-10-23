#!/bin/bash
set -euo pipefail
# The pinned release uses build/utils.sh (not build_utils.sh in newer docs).
export EXPANDED_CODE_SIGN_IDENTITY="-"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="Ad Hoc"
source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"
install_python Vendor/Python.xcframework
mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/packages"
rsync -a --exclude='__pycache__' "$PROJECT_DIR/Vendor/PythonPackages/" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/packages/"
