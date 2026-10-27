#!/bin/bash
# Start booting while Xcode compiles; the test step still waits for readiness.
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
destination=$("$script_dir/select-ios-simulator.sh")
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from apple_nightly_ui import start_simulator; start_simulator(sys.argv[2])' \
    "$script_dir" "$destination" >&2
printf '%s\n' "$destination"
