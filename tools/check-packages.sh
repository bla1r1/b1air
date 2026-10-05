#!/usr/bin/env bash
# check-packages.sh — every name in the package lists for one family is a
# package (or something a package provides) in that family's repositories,
# asked of its own package manager. A name that is not there stops install.sh
# half way on a new machine; here it is found on every push instead.
#
#   tools/check-packages.sh <arch|debian|fedora|opensuse>
#
# Run in that family's container, with the repositories refreshed. A
# required name missing fails; an optional one (?name) is only reported —
# install.sh skips those that a release does not have.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/distro.sh
source "$here/lib/distro.sh"
family="${1:?usage: check-packages.sh <arch|debian|fedora|opensuse>}"

exists() {
    case "$family" in
        arch)     pacman -Sp --print-format %n "$1" >/dev/null 2>&1 ;;   # packages, groups, provides
        debian)   [[ -n "$(apt-cache showpkg "$1" 2>/dev/null | sed -n '/^Versions:/,/^Reverse Depends:/p' | sed '1d;$d')" ]] \
                      || apt-cache showpkg "$1" 2>/dev/null | sed -n '/^Reverse Provides:/,$p' | sed '1d' | grep -q . ;;
        fedora)   [[ -n "$(dnf -q repoquery --whatprovides "$1" 2>/dev/null)" ]] ;;
        opensuse) zypper -n -q what-provides "$1" >/dev/null 2>&1 ;;
        *) echo "check-packages: unknown family $family" >&2; exit 2 ;;
    esac
}

missing=0 absent_optional=0 checked=0
check_list() {
    local list="$1" pkg
    [[ -f "$list" ]] || return 0
    for pkg in $(read_package_list "$list" required); do
        checked=$((checked + 1))
        exists "$pkg" || { echo "MISSING  $pkg  ($list)"; missing=$((missing + 1)); }
    done
    for pkg in $(read_package_list "$list" optional); do
        checked=$((checked + 1))
        exists "$pkg" || { echo "optional $pkg is not in this release  ($list)"; absent_optional=$((absent_optional + 1)); }
    done
}

check_list "$here/packages/$family.txt"
check_list "$here/packages/swayfx-build/$family.txt"
check_list "$here/packages/quickshell-build/$family.txt"

# The AUR, for Arch: asked over its web API.
if [[ "$family" == arch && -f "$here/packages/arch-aur.txt" ]] && command -v curl >/dev/null; then
    for pkg in $(read_package_list "$here/packages/arch-aur.txt" required) $(read_package_list "$here/packages/arch-aur.txt" optional); do
        checked=$((checked + 1))
        curl -fsS "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=$pkg" | grep -q '"resultcount":1' \
            || { echo "MISSING  $pkg  (AUR)"; missing=$((missing + 1)); }
    done
fi

echo "check-packages ($family): $checked names, $missing missing, $absent_optional optional ones not in this release"
[[ $missing -eq 0 ]]
