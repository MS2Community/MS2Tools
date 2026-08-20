#!/bin/bash
# Checks that this machine's MS2Create produces the archive bytes that every other
# machine produces, before its output is deployed or ingested.
#
# The reference hashes below were produced by the linux-x64 build of MS2Create on
# 15 August 2026 and reproduced by a linux-arm64 build on 20 August 2026. A mismatch
# means archives built here differ from archives built elsewhere for the same input,
# which no one can reproduce and which must not be shipped.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: determinism-check.sh [--ms2create <path>] [--xml-repo <path>]

  --ms2create <path>  MS2Create binary to test. Defaults to publish/<rid>/MS2Create.
  --xml-repo <path>   Checkout of LithMS2-XML holding the source folders.
                      Defaults to ../LithMS2-XML.

Each case names a source folder, the commit that last changed it, and the expected
sha256 of the resulting .m2d and .m2h. Re-pin a case only when its source folder
changes, and record the new commit alongside the new hashes.
EOF
}

# "<source folder>|<archive name>|<source commit>|<m2d sha256>|<m2h sha256>"
CASES=(
    "Model/Camera|Camera|c2493836d6|210013bd1aefd8c74e5905120943f98f54c10e43ad86c3aa8e99616196ca72b1|4142e4d75ab68f338ae96f6906e93419332ae0d40aad8914c98128054f385f1d"
    "Model/Path|Path|c2493836d6|09dfbc668456c5cc53f3cb16ac20f3b1c23c779de50b099e517db8686dfabaa5|"
    "Model/Tool|Tool|c2493836d6|fd1f02d491a72501bbbc1344eb4f551bd1ce5d1a2bdc260f0eae501e86a3c4a5|"
)

MS2CREATE=""
XML_REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ms2create) MS2CREATE="${2:-}"; [[ -z "$MS2CREATE" ]] && { echo "--ms2create needs a value." >&2; exit 2; }; shift ;;
        --xml-repo) XML_REPO="${2:-}"; [[ -z "$XML_REPO" ]] && { echo "--xml-repo needs a value." >&2; exit 2; }; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

cd "$(dirname "$0")"

if [[ -z "$MS2CREATE" ]]; then
    case "$(uname -s)" in
        Linux) os="linux"; exe="" ;;
        Darwin) os="osx"; exe="" ;;
        MINGW*|MSYS*|CYGWIN*) os="win"; exe=".exe" ;;
        *) echo "Cannot map $(uname -s) to a runtime identifier. Pass --ms2create." >&2; exit 2 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "Cannot map $(uname -m) to a runtime identifier. Pass --ms2create." >&2; exit 2 ;;
    esac
    MS2CREATE="./publish/$os-$arch/MS2Create$exe"
fi

if [[ ! -x "$MS2CREATE" ]]; then
    echo "$MS2CREATE is missing or not executable. Run ./publish.sh first." >&2
    exit 2
fi

[[ -z "$XML_REPO" ]] && XML_REPO="../LithMS2-XML"
if [[ ! -d "$XML_REPO" ]]; then
    echo "$XML_REPO is not a directory. Pass --xml-repo." >&2
    exit 2
fi

if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    echo "Need sha256sum or shasum to hash the archives." >&2
    exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

failed=0
for entry in "${CASES[@]}"; do
    IFS='|' read -r src name commit want_m2d want_m2h <<< "$entry"
    if [[ ! -d "$XML_REPO/$src" ]]; then
        echo "SKIP $name: $XML_REPO/$src not found"
        continue
    fi

    # A source folder that moved on from the pinned commit no longer produces the
    # recorded bytes, so a mismatch would say "not deterministic" when it only means
    # "different input". Both sides are resolved to full hashes: %h honours core.abbrev,
    # so comparing abbreviations makes every case skip under a different setting, and
    # the run then reports success without hashing a single archive.
    if ! pinned="$(git -C "$XML_REPO" rev-parse --verify --quiet "$commit^{commit}")"; then
        echo "FAIL $name: pinned commit $commit is not in $XML_REPO" >&2
        echo "  Fetch it, or re-pin this case if the folder has legitimately changed." >&2
        failed=1
        continue
    fi

    actual_commit="$(git -C "$XML_REPO" log -1 --format=%H -- "$src")"
    if [[ "$actual_commit" != "$pinned" ]]; then
        echo "SKIP $name: $src last changed in ${actual_commit:0:10}, hashes are pinned to $commit"
        continue
    fi
    if [[ -n "$(git -C "$XML_REPO" status --porcelain -- "$src")" ]]; then
        echo "SKIP $name: $src has uncommitted changes, so the input is not the pinned one"
        continue
    fi

    if ! "$MS2CREATE" "$XML_REPO/$src" "$workdir" "$name" MS2F >/dev/null; then
        echo "FAIL $name: MS2Create exited non-zero" >&2
        failed=1
        continue
    fi

    if [[ ! -f "$workdir/$name.m2d" || ! -f "$workdir/$name.m2h" ]]; then
        echo "FAIL $name: MS2Create produced no archive" >&2
        failed=1
        continue
    fi

    got_m2d="$(sha256 "$workdir/$name.m2d")"
    if [[ "$got_m2d" != "$want_m2d" ]]; then
        echo "FAIL $name.m2d" >&2
        echo "  expected $want_m2d" >&2
        echo "  got      $got_m2d" >&2
        failed=1
    else
        echo "OK   $name.m2d"
    fi

    if [[ -n "$want_m2h" ]]; then
        got_m2h="$(sha256 "$workdir/$name.m2h")"
        if [[ "$got_m2h" != "$want_m2h" ]]; then
            echo "FAIL $name.m2h" >&2
            echo "  expected $want_m2h" >&2
            echo "  got      $got_m2h" >&2
            failed=1
        else
            echo "OK   $name.m2h"
        fi
    fi

    rm -f "$workdir/$name.m2d" "$workdir/$name.m2h"
done

if [[ "$failed" -ne 0 ]]; then
    echo "Archive bytes differ from the reference. Do not deploy output from this build." >&2
    exit 1
fi
echo "All cases match the reference hashes."
