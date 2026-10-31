#!/bin/sh
# ==============================================================================
# ooxz Universal Installer & Lifecycle Manager
# "High-ratio LZMA2 compressor utilizing dictionary matching and thread pools."
#
# Usage:
#   curl -fsSL https://openooda-tooxz.github.io/ooxz/install.sh | bash
#
# Options:
#   --prefix <dir>       Installation directory (default: /usr/local/bin or ~/.local/bin)
#   --apt, --deb         Install Debian package (.deb) via apt/dpkg
#   --dnf, --rpm         Install RPM package (.rpm) via dnf
#   --pkgbuild, --arch   Install Arch Linux package via PKGBUILD / makepkg
#   --dry-run            Simulate installation or uninstallation without filesystem writes
#   --uninstall          Cleanly remove ooxz binary, packages, and symlinks
#   -h, --help           Show this help message
# ==============================================================================

set -eu

REPO="openOODA-tooxz/ooxz"
GITHUB_URL="https://github.com/${REPO}"
VERSION_PIN="v0.1.0"
RAW_VERSION="0.1.0"

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    CYAN="\033[38;5;51m"
    GREEN="\033[38;5;82m"
    YELLOW="\033[38;5;220m"
    DIM="\033[38;5;242m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    CYAN="" GREEN="" YELLOW="" DIM="" BOLD="" RESET=""
fi

say()  { printf '%b\n' "$*"; }
ok()   { say "  ${GREEN}✔${RESET} $*"; }
warn() { say "  ${YELLOW}!${RESET} $*"; }
err()  { say "  ${YELLOW}ERROR:${RESET} $*" >&2; }
step() { say ""; say " ${CYAN}${BOLD}$*${RESET}"; }

PREFIX=""
DRY_RUN=0
UNINSTALL=0
MODE="binary"

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        --apt|--deb)
            MODE="deb"
            shift
            ;;
        --dnf|--rpm)
            MODE="rpm"
            shift
            ;;
        --pkgbuild|--arch)
            MODE="arch"
            shift
            ;;
        -h|--help)
            say "Usage: install.sh [options]"
            say "Options:"
            say "  --prefix <dir>       Target installation directory"
            say "  --apt, --deb         Install Debian package via apt/dpkg"
            say "  --dnf, --rpm         Install RPM package via dnf"
            say "  --pkgbuild, --arch   Install Arch Linux package via PKGBUILD / makepkg"
            say "  --dry-run            Simulate installation or uninstallation without disk writes"
            say "  --uninstall          Remove ooxz from system paths and package managers"
            say "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            exit 2
            ;;
    esac
done

resolve_prefix() {
    if [ -n "$PREFIX" ]; then
        return
    fi
    if [ "$(id -u)" -eq 0 ]; then
        PREFIX="/usr/local/bin"
    elif [ -d "$HOME/.local/bin" ] && printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
        PREFIX="$HOME/.local/bin"
    elif [ -w "/usr/local/bin" ]; then
        PREFIX="/usr/local/bin"
    else
        PREFIX="$HOME/.local/bin"
    fi
}

resolve_prefix

# --- Clean Uninstaller Implementation -----------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    step "Cleanly uninstalling ooxz"
    REMOVED_ANY=0

    # 1. Check Debian package manager
    if command -v dpkg >/dev/null 2>&1 && dpkg -s ooxz >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            say "  [dry-run] Would remove Debian package: ooxz"
        else
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get remove -y -qq ooxz 2>/dev/null || sudo dpkg -r ooxz
            else
                sudo dpkg -r ooxz
            fi
            ok "Removed Debian package: ooxz"
        fi
        REMOVED_ANY=1
    fi

    # 2. Check RPM package manager
    if command -v rpm >/dev/null 2>&1 && rpm -q ooxz >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            say "  [dry-run] Would remove RPM package: ooxz"
        else
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf remove -y -q ooxz 2>/dev/null || sudo rpm -e ooxz
            else
                sudo rpm -e ooxz
            fi
            ok "Removed RPM package: ooxz"
        fi
        REMOVED_ANY=1
    fi

    # 3. Check Arch pacman
    if command -v pacman >/dev/null 2>&1 && pacman -Q ooxz-bin >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            say "  [dry-run] Would remove Pacman package: ooxz-bin"
        else
            sudo pacman -R --noconfirm ooxz-bin
            ok "Removed Pacman package: ooxz-bin"
        fi
        REMOVED_ANY=1
    fi

    # 4. Check standalone binaries in standard paths
    CANDIDATE_PATHS="$PREFIX/ooxz $PREFIX/ooxz-uninstall /usr/local/bin/ooxz /usr/local/bin/ooxz-uninstall /usr/bin/ooxz /usr/bin/ooxz-uninstall $HOME/.local/bin/ooxz $HOME/.local/bin/ooxz-uninstall"
    for p in $CANDIDATE_PATHS; do
        if [ -f "$p" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                say "  [dry-run] Would remove binary: $p"
            else
                if [ -w "$p" ] || [ -w "$(dirname "$p")" ]; then
                    rm -f "$p"
                else
                    sudo rm -f "$p"
                fi
                ok "Removed binary: $p"
            fi
            REMOVED_ANY=1
        fi
    done

    if [ "$REMOVED_ANY" -eq 0 ]; then
        warn "No existing ooxz installation found in system paths or package managers."
    else
        ok "ooxz clean uninstallation complete."
    fi
    exit 0
fi

# --- Package Manager Installs (APT / DNF / PKGBUILD) ---------------------------

# verify_sha256 <file> <url>: fetch the .sha256 sidecar and verify; refuse on mismatch/missing.
verify_sha256() {
    local f="$1" url="$2"
    local sf tmp
    sf="$(mktemp --suffix=.sha256)"
    if ! curl -fsSL --max-time 15 "${url}.sha256" -o "$sf" 2>/dev/null; then
        rm -f "$sf"
        err "missing SHA-256 sidecar for $url; refuse unsigned install"
        return 1
    fi
    local expected actual
    expected="$(awk '{print $1}' "$sf" | tr -d '\r\n ')"
    rm -f "$sf"
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$f" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$f" | awk '{print $1}')"
    else
        err "no sha256sum/shasum; refuse unsigned install"
        return 1
    fi
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
        err "SHA-256 mismatch for $f (expected $expected, got $actual)"
        return 1
    fi
    ok "SHA-256 verified: ${actual:0:16}..."
    return 0
}
if [ "$MODE" = "deb" ]; then
    step "Installing ooxz via Debian package (.deb)"
    DEB_URL="${GITHUB_URL}/releases/download/${VERSION_PIN}/ooxz_${RAW_VERSION}-1_amd64.deb"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  [dry-run] Would download and install $DEB_URL"
        ok "Dry run complete."
        exit 0
    fi
    TMP_DEB="$(mktemp --suffix=.deb)"
    if [ -f "./dist/ooxz_${RAW_VERSION}-1_amd64.deb" ]; then
        TMP_DEB="./dist/ooxz_${RAW_VERSION}-1_amd64.deb"
    else
        curl -fsSL "$DEB_URL" -o "$TMP_DEB"
        verify_sha256 "$TMP_DEB" "$DEB_URL" || { rm -f "$TMP_DEB"; exit 1; }
    fi
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y -qq "$TMP_DEB"
    else
        sudo dpkg -i "$TMP_DEB"
    fi
    ok "Installed ooxz Debian package successfully."
    exit 0
fi

if [ "$MODE" = "rpm" ]; then
    step "Installing ooxz via RPM package (.rpm)"
    RPM_URL="${GITHUB_URL}/releases/download/${VERSION_PIN}/ooxz-${RAW_VERSION}-1.x86_64.rpm"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  [dry-run] Would download and install $RPM_URL"
        ok "Dry run complete."
        exit 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        if [ -f "./dist/ooxz-${RAW_VERSION}-1.x86_64.rpm" ]; then
            sudo dnf install -y -q "./dist/ooxz-${RAW_VERSION}-1.x86_64.rpm"
        else
            TMP_RPM2="$(mktemp --suffix=.rpm)"
            curl -fsSL "$RPM_URL" -o "$TMP_RPM2"
            verify_sha256 "$TMP_RPM2" "$RPM_URL" || { rm -f "$TMP_RPM2"; exit 1; }
            sudo dnf install -y -q "$TMP_RPM2"
            rm -f "$TMP_RPM2"
        fi
    else
        TMP_RPM="$(mktemp --suffix=.rpm)"
        curl -fsSL "$RPM_URL" -o "$TMP_RPM"
        verify_sha256 "$TMP_RPM" "$RPM_URL" || { rm -f "$TMP_RPM"; exit 1; }
        sudo rpm -Uvh "$TMP_RPM"
    fi
    ok "Installed ooxz RPM package successfully."
    exit 0
fi

if [ "$MODE" = "arch" ]; then
    step "Installing ooxz via Arch PKGBUILD"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  [dry-run] Would build and install package using packaging/PKGBUILD"
        ok "Dry run complete."
        exit 0
    fi
    TMP_DIR="$(mktemp -d)"
    if [ -f "./packaging/PKGBUILD" ]; then
        cp ./packaging/PKGBUILD "$TMP_DIR/"
    else
        curl -fsSL "https://raw.githubusercontent.com/${REPO}/${VERSION_PIN}/packaging/PKGBUILD" -o "$TMP_DIR/PKGBUILD"
    fi
    (cd "$TMP_DIR" && makepkg -si --noconfirm)
    rm -rf "$TMP_DIR"
    ok "Installed ooxz Arch package successfully."
    exit 0
fi

# --- Standalone Binary Universal Install --------------------------------------
step "Installing ooxz ($VERSION_PIN)"
say "  Target location: ${BOLD}$PREFIX/ooxz${RESET}"

if [ "$DRY_RUN" -eq 1 ]; then
    say "  [dry-run] Would download and install to $PREFIX/ooxz"
    ok "Dry run complete."
    exit 0
fi

mkdir -p "$PREFIX"

if [ -f "./dist/ooxz" ]; then
    cp "./dist/ooxz" "$PREFIX/ooxz"
    chmod +x "$PREFIX/ooxz"
    ok "Installed local binary to $PREFIX/ooxz"
else
    DOWNLOAD_URL="${GITHUB_URL}/releases/download/${VERSION_PIN}/ooxz-linux-x86_64"
    TMP_BIN="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$DOWNLOAD_URL" -o "$TMP_BIN"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_BIN" "$DOWNLOAD_URL"
    else
        err "Neither curl nor wget is available."
        exit 1
    fi
    verify_sha256 "$TMP_BIN" "$DOWNLOAD_URL" || { rm -f "$TMP_BIN"; exit 1; }
    chmod +x "$TMP_BIN"
    mv "$TMP_BIN" "$PREFIX/ooxz"
    ok "Downloaded and installed $VERSION_PIN to $PREFIX/ooxz"
fi

if [ -f "./uninstall.sh" ]; then
    cp "./uninstall.sh" "$PREFIX/ooxz-uninstall"
    chmod +x "$PREFIX/ooxz-uninstall"
    ok "Installed companion uninstaller to $PREFIX/ooxz-uninstall"
else
    UNINSTALL_URL="https://raw.githubusercontent.com/${REPO}/${VERSION_PIN}/uninstall.sh"
    TMP_UNINSTALL="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$UNINSTALL_URL" -o "$TMP_UNINSTALL" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_UNINSTALL" "$UNINSTALL_URL" 2>/dev/null || true
    fi
    if [ -s "$TMP_UNINSTALL" ]; then
        chmod +x "$TMP_UNINSTALL"
        mv "$TMP_UNINSTALL" "$PREFIX/ooxz-uninstall"
        ok "Installed companion uninstaller to $PREFIX/ooxz-uninstall"
    else
        rm -f "$TMP_UNINSTALL"
    fi
fi

if "$PREFIX/ooxz" --version >/dev/null 2>&1; then
    ok "Verified: $("$PREFIX/ooxz" --version)"
else
    warn "Installed binary failed execution check."
fi
