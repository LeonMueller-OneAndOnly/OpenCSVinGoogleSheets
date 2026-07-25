#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="$root/dist/CSVtoSheets.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/bin/CSVtoSheets" "$app/Contents/MacOS/CSVtoSheets-core"
xcrun swiftc -parse-as-library "$root/macos/CSVtoSheetsLauncher.swift" -o "$app/Contents/MacOS/CSVtoSheets"
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"

if [[ -f "$root/credentials.json" ]]; then
  cp "$root/credentials.json" "$app/Contents/Resources/credentials.json"
else
  print "Hinweis: credentials.json fehlt. Vor der Nutzung in Contents/Resources ablegen." >&2
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
