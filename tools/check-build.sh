#!/bin/sh
# Proves the build number is the same in all three places. A mismatch tells
# players to update to a build that is not there, or hides a build that is.
#
#   sh tools/check-build.sh            check the working copy
#   sh tools/check-build.sh --live     also check what GitHub Pages serves
set -e
cd "$(dirname "$0")/.."

html=$(grep -m1 -o 'build: *[0-9]\+' index.html | grep -o '[0-9]\+')
cap=$(grep -m1 -o '"build": *[0-9]\+' Version.json | grep -o '[0-9]\+')
low=$(grep -m1 -o '"build": *[0-9]\+' version.json | grep -o '[0-9]\+')

echo "index.html CONFIG.build : $html"
echo "Version.json            : $cap"
echo "version.json            : $low"

fail=0
[ "$html" = "$cap" ] || { echo "MISMATCH: index.html vs Version.json"; fail=1; }
[ "$html" = "$low" ] || { echo "MISMATCH: index.html vs version.json"; fail=1; }
[ "$fail" = 0 ] && echo "OK: all three agree on build $html"

if [ "$1" = "--live" ]; then
  base="https://prasidhajagtap.github.io/puzzle_abg1"
  echo
  for f in Version.json version.json; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$base/$f?t=$(date +%s)")
    b=$(curl -s "$base/$f?t=$(date +%s)" | grep -m1 -o '"build": *[0-9]\+' | grep -o '[0-9]\+' || true)
    echo "live $f -> HTTP $code  build ${b:-?}"
    [ "$code" = "200" ] || { echo "  ^ old copies of the game rely on this file. A 404 here strands them."; fail=1; }
  done
fi

exit $fail
