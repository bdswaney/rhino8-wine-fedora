#!/usr/bin/env bash
#
# install.sh — Rhino 8 on Fedora (KDE Plasma / Wayland) with Wine
#
# Runs Rhino 8 under a patched Wine 11.18 build installed in your home
# directory. Your system Wine is not touched. Nothing here needs sudo.
#
# Usage:
#   ./install.sh /path/to/rhino_en-us_8.x.exe     install Rhino 8
#   ./install.sh --kde-scaling                    only apply the KDE X11 scaling fix
#   ./install.sh --help
#
# What it does:
#   1. Downloads the pre-built patched Wine (SHA-256 verified) to ~/.local/share/wine-rhino
#   2. Creates a fresh 64-bit prefix at ~/.local/share/wineprefixes/rhino8
#   3. Runs the Rhino installer (a GUI window; click through it)
#   4. Installs a launcher at ~/.local/bin/rhino8 and an application-menu entry
#   5. Optionally switches KDE to upscale X11 apps so the UI is readable on HiDPI
#
set -euo pipefail

WINE_URL="https://github.com/Jabern/rhino-linux/releases/download/v1.0.0/wine-rhino-11.18-x86_64.tar.xz"
WINE_SHA256="59b3b39f0aa81178da3c87831243edb03432775f6482e31b054783d634fe2e6f"

WINE_DIR="$HOME/.local/share/wine-rhino"
PREFIX="${RHINO_PREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rhino8-wine-fedora"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
# KDE: let the compositor upscale X11 apps (Wine does not honor KDE scaling)
# ---------------------------------------------------------------------------
apply_kde_scaling() {
    command -v kwriteconfig6 >/dev/null 2>&1 || { warn "kwriteconfig6 not found; skipping KDE scaling (not KDE Plasma 6?)"; return 0; }
    info "Setting KDE 'Legacy applications (X11)' to 'Scaled by the system'..."
    # The --notify flag matters: without it KWin ignores the change until relogin.
    kwriteconfig6 --notify --file kdeglobals --group KScreen --key XwaylandClientsScale false
    info "Done. Undo in System Settings > Display & Monitor > Legacy applications (X11)."
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
INSTALLER=""
KDE_SCALING=0
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --kde-scaling) apply_kde_scaling; exit 0 ;;
    "") usage; exit 1 ;;
    *) INSTALLER="$1" ;;
esac
[ "${2:-}" = "--kde-scaling" ] && KDE_SCALING=1
[ -f "$INSTALLER" ] || die "installer not found: $INSTALLER"

# ---------------------------------------------------------------------------
# 1. Dependencies (Vulkan is needed for the viewport; everything else is in the tarball)
# ---------------------------------------------------------------------------
info "Checking dependencies..."
missing=()
for pkg in vulkan-loader mesa-vulkan-drivers freetype gnutls; do
    rpm -q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [ ${#missing[@]} -gt 0 ]; then
    die "missing packages: ${missing[*]}
   Install them with:  sudo dnf install ${missing[*]}"
fi

# ---------------------------------------------------------------------------
# 2. Patched Wine
# ---------------------------------------------------------------------------
WINE="$WINE_DIR/bin/wine"
WINESERVER="$WINE_DIR/bin/wineserver"
if [ -x "$WINE" ]; then
    info "Patched Wine already present: $("$WINE" --version)"
else
    mkdir -p "$CACHE_DIR" "$WINE_DIR"
    tarball="$CACHE_DIR/$(basename "$WINE_URL")"
    if [ ! -f "$tarball" ] || ! echo "$WINE_SHA256  $tarball" | sha256sum -c --status; then
        info "Downloading patched Wine 11.18 (~63 MB)..."
        curl -fL --progress-bar -o "$tarball.part" "$WINE_URL"
        echo "$WINE_SHA256  $tarball.part" | sha256sum -c --status \
            || { rm -f "$tarball.part"; die "SHA-256 mismatch on downloaded Wine tarball"; }
        mv -f "$tarball.part" "$tarball"
    fi
    info "Extracting to $WINE_DIR..."
    tar -xf "$tarball" -C "$WINE_DIR"
    [ -x "$WINE" ] || die "extraction failed; $WINE not found"
    info "Patched Wine ready: $("$WINE" --version)"
fi

# ---------------------------------------------------------------------------
# 3. Prefix + installer
# ---------------------------------------------------------------------------
export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all
mkdir -p "$(dirname "$PREFIX")"
if [ -d "$PREFIX/drive_c" ]; then
    warn "prefix already exists at $PREFIX; reusing it"
else
    info "Initializing Wine prefix at $PREFIX..."
    "$WINE" wineboot -u
    "$WINESERVER" -w
fi

info "Launching the Rhino installer. Click through the window that opens."
info "(It bundles its own .NET 8, WebView2, and VC++ runtimes. No winetricks needed.)"
"$WINE" "$INSTALLER" || true
"$WINESERVER" -w 2>/dev/null || true

RHINO_EXE="$PREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
[ -f "$RHINO_EXE" ] || die "Rhino.exe not found after install. Did the installer finish?"
info "Found: $RHINO_EXE"

# ---------------------------------------------------------------------------
# 4. Launcher + menu entry
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR" "$APPS_DIR"
install -m 755 "$SCRIPT_DIR/rhino8" "$BIN_DIR/rhino8"

cat > "$APPS_DIR/rhino8.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Rhino 8
Comment=Rhinoceros 3D (Wine)
Exec=$BIN_DIR/rhino8 %F
Icon=$PREFIX/drive_c/Program Files/Rhino 8/System/rhino.ico
Terminal=false
Categories=Graphics;3DGraphics;Engineering;
MimeType=application/x-3dm;
StartupWMClass=rhino.exe
EOF
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
info "Launcher installed: $BIN_DIR/rhino8 and application-menu entry 'Rhino 8'"

# ---------------------------------------------------------------------------
# 5. KDE scaling (optional)
# ---------------------------------------------------------------------------
[ "$KDE_SCALING" -eq 1 ] && apply_kde_scaling

cat <<EOF

$(info "Done.")

Launch Rhino from the application menu or with:  rhino8

First launch asks you to sign in with your Rhino account. If the browser
lands on http://127.0.0.1:1717/ and cannot connect, run:  rhino8 --fresh

If the UI is tiny on a HiDPI screen, run:  ./install.sh --kde-scaling
EOF
