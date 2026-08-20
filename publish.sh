#!/bin/bash
# Publishes the MS2Tools CLI tools as self-contained single-file binaries.
#
# Self-contained rather than framework-dependent because MS2Lib compresses archive
# payloads with System.IO.Compression.ZLibStream, and the exact compressed bytes are
# not a stable contract across .NET releases. .NET 9 switched the deflate backend from
# zlib to zlib-ng, so a framework-dependent build rolled forward onto an installed .NET
# 9 or 10 runtime would produce different archive bytes from the same input. Embedding
# the .NET 8 runtime pins the deflate implementation to the one every existing archive
# was built with.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: publish.sh [--rid <runtime id>] [--out <directory>] [--project <name>]

  --rid <id>        Runtime identifier to publish for. Defaults to this machine's.
                    Examples: linux-x64, linux-arm64, win-x64, osx-arm64.
  --out <dir>       Output directory. Defaults to ./publish/<rid>.
  --project <name>  Publish one project instead of all three. Repeatable.
                    Known: MS2Create, MS2Extract, MS2FileHeaderExporter.
EOF
}

detect_rid() {
    local os arch
    case "$(uname -s)" in
        Linux) os="linux" ;;
        Darwin) os="osx" ;;
        MINGW*|MSYS*|CYGWIN*) os="win" ;;
        *) echo "Cannot map $(uname -s) to a .NET runtime identifier. Pass --rid." >&2; exit 2 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "Cannot map $(uname -m) to a .NET runtime identifier. Pass --rid." >&2; exit 2 ;;
    esac
    echo "$os-$arch"
}

RID=""
OUT=""
PROJECTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rid) RID="${2:-}"; [[ -z "$RID" ]] && { echo "--rid needs a value." >&2; exit 2; }; shift ;;
        --out) OUT="${2:-}"; [[ -z "$OUT" ]] && { echo "--out needs a value." >&2; exit 2; }; shift ;;
        --project) [[ -z "${2:-}" ]] && { echo "--project needs a value." >&2; exit 2; }; PROJECTS+=("$2"); shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[[ -z "$RID" ]] && RID="$(detect_rid)"
[[ -z "$OUT" ]] && OUT="./publish/$RID"
[[ ${#PROJECTS[@]} -eq 0 ]] && PROJECTS=(MS2Create MS2Extract MS2FileHeaderExporter)

cd "$(dirname "$0")"

echo "Publishing for $RID into $OUT"
for project in "${PROJECTS[@]}"; do
    if [[ ! -f "$project/$project.csproj" ]]; then
        echo "No such project: $project" >&2
        exit 2
    fi
    echo "  $project"
    dotnet publish "$project/$project.csproj" \
        -c Release \
        -r "$RID" \
        --self-contained true \
        -o "$OUT"
done

echo "Done. Binaries are in $OUT"
