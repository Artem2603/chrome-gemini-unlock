#!/usr/bin/env bash
# Builds the files of a release: the ZIP users download, its SHA-256, and the release notes taken
# from the tag's section of CHANGELOG.md. Run from the repository root:
#
#   bash tools/build-release.sh v1.0.0 dist [git-ref]      (git-ref defaults to the tag itself)
set -euo pipefail

tag="${1:?usage: build-release.sh <tag> <out-dir> [git-ref]}"
out="${2:?usage: build-release.sh <tag> <out-dir> [git-ref]}"
ref="${3:-$tag}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The tag must look like v1.2.3, got '$tag'" >&2; exit 1; }
version="${tag#v}"
name="chrome-gemini-unlock-$tag"
files=(chrome-gemini-unlock.bat chrome-gemini-unlock.ps1 README.md README.ru.md README.fr.md README.de.md CHANGELOG.md LICENSE)

mkdir -p "$out"
# git archive applies .gitattributes: the scripts keep CRLF, and the .ps1 keeps the BOM that
# Windows PowerShell 5.1 needs to read its non-English messages
git archive --format=zip --prefix="$name/" -o "$out/$name.zip" "$ref" -- "${files[@]}"

# What users run must arrive intact. The checks read extracted files: piping unzip into head would
# end unzip with SIGPIPE, which pipefail turns into a silent failure
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
unzip -q "$out/$name.zip" -d "$check"
bom="$(head -c 3 "$check/$name/chrome-gemini-unlock.ps1" | od -An -tx1 | tr -d ' \n')"
[ "$bom" = "efbbbf" ] || { echo "chrome-gemini-unlock.ps1 lost its UTF-8 BOM" >&2; exit 1; }
for f in chrome-gemini-unlock.ps1 chrome-gemini-unlock.bat; do
    lines="$(wc -l < "$check/$name/$f")"
    crlf="$(grep -c $'\r$' "$check/$name/$f" || true)"
    [ "$lines" -gt 0 ] && [ "$lines" = "$crlf" ] || { echo "$f does not have CRLF line endings ($crlf of $lines)" >&2; exit 1; }
done
for f in "${files[@]}"; do
    [ -s "$check/$name/$f" ] || { echo "$f is missing from the ZIP" >&2; exit 1; }
done

(cd "$out" && sha256sum "$name.zip" > "$name.zip.sha256")
hash="$(cut -d' ' -f1 "$out/$name.zip.sha256")"

# Release notes: the CHANGELOG section "## v1.2.3 ..." up to the next "## "
notes="$out/notes.md"
git show "$ref:CHANGELOG.md" | awk -v v="$version" '
    $0 ~ "^## v" v "( |$)" { found = 1; next }
    found && /^## / { exit }
    found { print }' > "$notes"
grep -q '[^[:space:]]' "$notes" || { echo "CHANGELOG.md has no section '## v$version'" >&2; exit 1; }
cat >> "$notes" <<NOTES

---
**SHA-256** of \`$name.zip\`: \`$hash\`

Check it in PowerShell in the download folder; it must print \`True\`:
\`\`\`powershell
(Get-FileHash .\\$name.zip -Algorithm SHA256).Hash -eq (Get-Content .\\$name.zip.sha256).Split(' ')[0]
\`\`\`
NOTES

echo "Built $out/$name.zip"
echo "SHA-256 $hash"
