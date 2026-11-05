#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-engine.sh
python3 Checks/native_engine.py
