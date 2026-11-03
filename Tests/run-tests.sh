#!/bin/bash
# Compiles the window-free parts of NotizEditor together with Tests/core-test.swift and runs the tests.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
S=Sources/NotizEditor
swiftc -O -parse-as-library -swift-version 5 -module-name NotizEditorTests \
    $S/Localization.swift $S/TextFile.swift $S/Syntax.swift $S/Highlighter.swift $S/TextCommands.swift \
    Tests/core-test.swift -o build/core-tests
build/core-tests
