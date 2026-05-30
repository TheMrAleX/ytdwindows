#!/usr/bin/env bash
# Instala ytdlinux en ~/.local y registra el esquema ytdlinux:// con xdg-mime.
# Uso:
#   ./install.sh              → build release + instalar
#   ./install.sh --debug      → usa build/linux/x64/debug/bundle (no rebuild)
#   ./install.sh --no-build   → no recompila, usa lo que haya en release
set -euo pipefail

MODE="release"
DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --debug)    MODE="debug"; DO_BUILD=0 ;;
    --no-build) DO_BUILD=0 ;;
    -h|--help)
      sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- Dependencias del sistema (solo aviso, no las tocamos)
command -v yt-dlp >/dev/null 2>&1 || warn "yt-dlp no detectado. Recomendado: pip install --user --break-system-packages -U yt-dlp"
command -v ffmpeg >/dev/null 2>&1 || warn "ffmpeg no detectado. Instala con: sudo apt install ffmpeg"

# --- Build
if [[ $DO_BUILD -eq 1 ]]; then
  command -v flutter >/dev/null 2>&1 || fail "flutter no encontrado en PATH"
  bold "==> flutter pub get"
  flutter pub get
  bold "==> flutter build linux --$MODE"
  flutter build linux --"$MODE"
fi

BUILD_DIR="$SCRIPT_DIR/build/linux/x64/$MODE/bundle"
[[ -x "$BUILD_DIR/ytdlinux" ]] || fail "No se encuentra binario en $BUILD_DIR/ytdlinux. Compila primero con flutter build linux --$MODE"

INSTALL_DIR="$HOME/.local/share/ytdlinux"
BIN_LINK="$HOME/.local/bin/ytdlinux"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/ytdlinux.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
ICON_FILE="$ICON_DIR/ytdlinux.png"

# --- Copiar bundle
bold "==> Copiando bundle a $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR"/*
cp -r "$BUILD_DIR"/* "$INSTALL_DIR"/
ok "bundle instalado"

# --- Symlink en PATH
mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_DIR/ytdlinux" "$BIN_LINK"
ok "symlink $BIN_LINK → $INSTALL_DIR/ytdlinux"

# --- Icono (intenta tomar del extension/icons como fallback)
mkdir -p "$ICON_DIR"
if [[ -f "$SCRIPT_DIR/../extension/icons/icon128.png" ]]; then
  cp "$SCRIPT_DIR/../extension/icons/icon128.png" "$ICON_FILE"
  ok "icono copiado a $ICON_FILE"
fi

# --- .desktop
bold "==> Registrando $DESKTOP_FILE"
mkdir -p "$DESKTOP_DIR"
sed "s|__BIN__|$INSTALL_DIR/ytdlinux|g" "$SCRIPT_DIR/linux/ytdlinux.desktop" > "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE"
ok ".desktop instalado"

# --- Refrescar bases de datos
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
  ok "update-desktop-database"
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

# --- Asociar scheme ytdlinux:// con la .desktop
xdg-mime default ytdlinux.desktop x-scheme-handler/ytdlinux
ok "xdg-mime default x-scheme-handler/ytdlinux → ytdlinux.desktop"

# --- Verificación final
echo
bold "Verificación:"
result="$(xdg-mime query default x-scheme-handler/ytdlinux || true)"
if [[ "$result" == "ytdlinux.desktop" ]]; then
  ok "scheme ytdlinux:// registrado correctamente"
else
  warn "xdg-mime devolvió: '$result' (esperado: ytdlinux.desktop)"
fi

echo
bold "Listo."
echo "Probar el deep link:"
echo "  xdg-open 'ytdlinux://download?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ'"
echo
echo "Si tu navegador (Chrome/Brave) ya recordó 'no permitir' antes,"
echo "ve a $DESKTOP_DIR y verifica el .desktop, y en chrome://settings/handlers"
echo "limpia el handler para youtube.com y vuelve a hacer click en el botón."
