#!/usr/bin/env bash
# Desinstala ytdlinux. NO toca yt-dlp, ffmpeg, ni dependencias del sistema.
set -euo pipefail

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }

INSTALL_DIR="$HOME/.local/share/ytdlinux"
BIN_LINK="$HOME/.local/bin/ytdlinux"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/ytdlinux.desktop"
ICON_FILE="$HOME/.local/share/icons/hicolor/128x128/apps/ytdlinux.png"

bold "==> Desinstalando ytdlinux"

# Symlink
if [[ -L "$BIN_LINK" || -f "$BIN_LINK" ]]; then
  rm -f "$BIN_LINK" && ok "borrado $BIN_LINK"
else
  warn "$BIN_LINK no existe"
fi

# Bundle
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR" && ok "borrado $INSTALL_DIR"
else
  warn "$INSTALL_DIR no existe"
fi

# .desktop
if [[ -f "$DESKTOP_FILE" ]]; then
  rm -f "$DESKTOP_FILE" && ok "borrado $DESKTOP_FILE"
else
  warn "$DESKTOP_FILE no existe"
fi

# Icono
if [[ -f "$ICON_FILE" ]]; then
  rm -f "$ICON_FILE" && ok "borrado $ICON_FILE"
fi

# Desasociar scheme — xdg-mime no tiene 'unset' directo. Lo más cercano:
# limpiar la entrada en mimeapps.list
MIMEAPPS="$HOME/.config/mimeapps.list"
if [[ -f "$MIMEAPPS" ]]; then
  # Borra cualquier línea que asocie ytdlinux.desktop
  if grep -q 'ytdlinux.desktop' "$MIMEAPPS"; then
    sed -i.bak '/ytdlinux.desktop/d' "$MIMEAPPS" && ok "limpiado mimeapps.list (backup .bak)"
  fi
  # Borra entradas x-scheme-handler/ytdlinux
  if grep -q 'x-scheme-handler/ytdlinux' "$MIMEAPPS"; then
    sed -i.bak '/x-scheme-handler\/ytdlinux/d' "$MIMEAPPS" && ok "limpiado scheme en mimeapps.list"
  fi
fi

# Refrescar bases
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
  ok "update-desktop-database"
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo
bold "Desinstalado."
echo "yt-dlp y ffmpeg NO fueron tocados (no los instalamos nosotros)."
echo
echo "Si quieres también borrar tus descargas:"
echo "  rm -rf ~/Videos/ytdlinux"
echo
echo "Y el .git del proyecto fuente queda intacto (clonado/compilado por ti)."
