#!/usr/bin/env bash
#
# Generates Jarvis.xcodeproj from project.yml and opens it in Xcode.
#
# Requirements: Xcode 15 or newer and XcodeGen (brew install xcodegen).

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  cat <<'MESSAGE'
XcodeGen is not installed. Install it with Homebrew:

    brew install xcodegen

or follow the manual setup steps in README.md, section "Building".
MESSAGE
  exit 1
fi

echo "Generating the Xcode project from project.yml"
xcodegen generate

if [ -d "Jarvis.xcodeproj" ]; then
  echo "Project generated. Opening Jarvis.xcodeproj"
  open Jarvis.xcodeproj
else
  echo "Project generation failed: Jarvis.xcodeproj was not created." >&2
  exit 1
fi
