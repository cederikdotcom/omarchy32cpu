#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Omarchy CPU has no Quickshell weather panel; the location helper the panel
# used remains a standalone CLI and keeps its contract.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

weather_location() {
  HOME="$test_tmp" "$ROOT/bin/omarchy-weather-location" "$@"
}

weather_location --set "Malibu" "34.02577,-118.7804"
[[ $(jq -c . "$test_tmp/.local/state/omarchy/settings/weather.json") == '{"name":"Malibu","latitude":34.02577,"longitude":-118.7804}' ]] || fail "weather location stores name and coordinates as JSON"
pass "weather location stores name and coordinates as JSON"

[[ $(weather_location) == "Malibu" ]] || fail "weather location returns the stored name"
pass "weather location returns the stored name"

weather_location --set "New York"
[[ $(jq -c . "$test_tmp/.local/state/omarchy/settings/weather.json") == '{"name":"New York"}' ]] || fail "weather location stores a bare name as JSON"
[[ $(weather_location) == "New York" ]] || fail "weather location returns a bare stored name"
pass "weather location stores and returns a bare name"

if weather_location --set "bad" "not,coords" 2>/dev/null; then
  fail "weather location rejects malformed coordinates"
fi
pass "weather location rejects malformed coordinates"

weather_location --clear
[[ ! -e "$test_tmp/.local/state/omarchy/settings/weather.json" ]] || fail "weather location clear removes the state file"
pass "weather location clear removes the state file"
