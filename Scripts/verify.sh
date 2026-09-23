#!/usr/bin/env bash
#
# Runs the static source checks. Use this before opening a pull request.
# Works without Xcode, so it also runs on a plain macOS or Linux machine
# with Python 3 available.

set -euo pipefail

cd "$(dirname "$0")/.."

python3 Scripts/check_sources.py
