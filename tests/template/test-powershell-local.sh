#!/usr/bin/env bash
set -euo pipefail
source_root=$(cd "$(dirname "$0")/../.." && pwd)
python3 "$source_root/tests/support/check-powershell-local.py"
