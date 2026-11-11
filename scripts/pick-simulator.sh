#!/usr/bin/env bash
# Prints the UDID of the newest available iPhone simulator, so CI does not
# depend on a device name that changes between Xcode versions.
set -euo pipefail
xcrun simctl list devices available -j \
  | jq -r '.devices | to_entries
           | map(select(.key | test("iOS")))
           | sort_by(.key) | reverse | .[0].value
           | map(select(.name | startswith("iPhone"))) | .[0].udid'
