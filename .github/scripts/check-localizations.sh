#!/bin/bash
# Fails when a string in the app's code has no translation in App/Localizable.xcstrings.
#
# Building does not add new strings to the catalog file (only Xcode's editor does), so
# the strings are extracted from the source again here, the same way Xcode does.
#
# Usage: .github/scripts/check-localizations.sh [language ...]   (default: zh-Hant)
set -euo pipefail

cd "$(dirname "$0")/../.."
languages=("${@:-zh-Hant}")
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

export_args=()
for language in "${languages[@]}"; do export_args+=(-exportLanguage "$language"); done
xcodebuild -exportLocalizations -project CaptionFitter.xcodeproj \
    -localizationPath "$workdir" "${export_args[@]}" > "$workdir/export.log" 2>&1 \
    || { cat "$workdir/export.log"; exit 1; }

status=0
for language in "${languages[@]}"; do
    xliff="$workdir/$language.xcloc/Localized Contents/$language.xliff"
    # Units of the app's catalog that should be translated but have no translated target.
    missing=$(xmllint --xpath '//*[local-name()="file"][@original="App/Localizable.xcstrings"]
        //*[local-name()="trans-unit"][not(@translate="no")]
        [not(*[local-name()="target"][@state="translated"])]/*[local-name()="source"]/text()' \
        "$xliff" 2>/dev/null || true)
    if [[ -n "$missing" ]]; then
        echo "Missing $language translations in App/Localizable.xcstrings:"
        echo "$missing" | sed 's/^/  /'
        status=1
    fi
done

if [[ $status -eq 0 ]]; then echo "All strings are translated (${languages[*]})."; fi
exit $status
