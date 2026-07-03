#!/usr/bin/env bash

set -e

# Verificar que se ejecute como root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script debe ejecutarse con sudo."
  exit 1
fi

# Detectar usuario real
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
ZSHRC="$USER_HOME/.zshrc"

echo "🚀 Iniciando la configuración de Chaotic-AUR y el entorno Hyprland..."

# -----------------------------
# 1. Importar las llaves GPG
# -----------------------------
echo "🔑 Importando la llave de Chaotic-AUR..."
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB

# -----------------------------
# 2. Instalar Keyring y Mirrorlist
# -----------------------------
echo "📥 Instalando chaotic-keyring y chaotic-mirrorlist..."
pacman -U --noconfirm \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# -----------------------------
# 3. Añadir repo a pacman.conf
# -----------------------------
CONF="/etc/pacman.conf"
REPO="\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist"

echo "📝 Añadiendo Chaotic-AUR a pacman.conf..."

if ! grep -q "\[chaotic-aur\]" "$CONF"; then
  echo -e "$REPO" >>"$CONF"
  echo "✅ Repo añadido a pacman.conf"
else
  echo "⚠️ Chaotic-AUR ya está en pacman.conf"
fi
# -----------------------------
# 4. Sincronizar y actualizar
# -----------------------------
echo "🔄 Actualizando bases de datos y sistema..."
pacman -Syyu --noconfirm

# -----------------------------
# 5. Instalar paquetes del entorno Hyprland
# -----------------------------
echo "🖥️ Instalando entorno Hyprland y utilidades..."

PACMAN_PKGS=(
  # Hyprland core
  hyprcursor
  hyprgraphics
  hypridle
  hyprland
  hyprland-guiutils
  hyprland-protocols
  hyprland-qt-support
  hyprlang
  hyprsunset
  # Terminal y editor
  kitty
  neovim
  neovim-qt
  # Utilidades de escritorio
  keyd
  libappindicator-gtk3
  localsend
  mission-center
  mpvpaper
  nwg-drawer
  nwg-look
  papirus-icon-theme
  swaybg
  swaync
  thunar
  tumbler
  wl-clip-persist
  wl-clipboard
  cliphist
  # Captura de pantalla
  grim
  slurp
  # Audio / brillo
  brightnessctl
  pavucontrol
  # Portales XDG
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  # Autenticación
  polkit-gnome
  # Wine / gaming
  wine-staging
  winetricks
  protontricks
  protonplus
  mangojuice
  steam
  gamemode
  gamescope
  # Aplicaciones
  ark
  telegram-desktop
  fastfetch
  discord
  brave-origin-bin
  octopi
  proton-vpn-gtk-app
  gpu-screen-recorder
  cava
  qt6ct
  gsettings-qt6
  gnome-firmware
  gearlever
  fzf
  eza
  yazi
  howdy-git
  # Temas
  adw-gtk-theme
  # BTRFS
  btrfs-assistant
  btrfs-progs
  snapper
  snap-pac
  # Display manager
  sddm
  # Xorg (para compatibilidad con apps que lo requieren)
  xorg-server
  xorg-xhost
  xorg-xinit
  # Red y servicios
  avahi
  firewalld
  # Plymouth (splash de arranque)
  plymouth
  # Arranque dual
  os-prober
  # Dependencias de Noctalia
  imagemagick
  python
  git
  wget
)

pacman -S --noconfirm --needed "${PACMAN_PKGS[@]}"

echo "✅ Paquetes de Hyprland instalados correctamente."

# -----------------------------
# 6. Instalar paru (AUR helper)
# -----------------------------
echo "📦 Instalando paru AUR helper..."

pacman -S --noconfirm --needed base-devel git

# Regla temporal en sudoers para que makepkg y paru no pidan contraseña
SUDOERS_TMP="/etc/sudoers.d/99-aur-install"
echo "$REAL_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"

PARU_TMP=$(mktemp -d)
chown "$REAL_USER:$REAL_USER" "$PARU_TMP"

sudo -u "$REAL_USER" git clone https://aur.archlinux.org/paru.git "$PARU_TMP/paru"

sudo -u "$REAL_USER" bash -c "cd '$PARU_TMP/paru' && makepkg -si --noconfirm"

rm -rf "$PARU_TMP"

echo "✅ paru instalado correctamente."

# -----------------------------
# 6.1. Instalar noctalia-shell-git con paru
# -----------------------------
echo "🎨 Instalando noctalia-shell-git..."

sudo -u "$REAL_USER" paru -S --noconfirm noctalia-shell-git

echo "✅ noctalia-shell-git instalado correctamente."

# Eliminar regla temporal de sudoers
rm -f "$SUDOERS_TMP"
echo "🔒 Regla temporal de sudoers eliminada."

# -----------------------------
# 7. Instalar tema SilentSDDM
# -----------------------------
echo "🎨 Instalando tema SilentSDDM..."

# Verificar y deshabilitar otros display managers activos
OTHER_DMS=(gdm lightdm ly lxdm xdm entrance nodm)
for dm in "${OTHER_DMS[@]}"; do
  if systemctl is-enabled "$dm" &>/dev/null; then
    echo "⚠️  Display manager '$dm' detectado y activo — deshabilitando..."
    systemctl disable "$dm"
    echo "✅ $dm deshabilitado."
  fi
done

# Dependencias adicionales requeridas por el tema
pacman -S --noconfirm --needed qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg

# Regla temporal de sudoers para instalación silenciosa del tema AUR
SUDOERS_TMP2="/etc/sudoers.d/98-sddm-theme"
echo "$REAL_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDOERS_TMP2"
chmod 440 "$SUDOERS_TMP2"

# Instalar desde AUR con paru como usuario real
sudo -u "$REAL_USER" paru -S --noconfirm sddm-silent-theme

# Eliminar regla temporal
rm -f "$SUDOERS_TMP2"
echo "🔒 Regla temporal de sudoers eliminada."

# Configurar /etc/sddm.conf para usar el tema
SDDM_CONF="/etc/sddm.conf"

echo "📝 Configurando $SDDM_CONF..."

cat >"$SDDM_CONF" <<'EOF'
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=silent
EOF

echo "✅ Tema SilentSDDM instalado y configurado."

# -----------------------------

# 8. Habilitar servicios
# -----------------------------
echo "🔥 Habilitando servicios del sistema..."

systemctl enable --now firewalld
systemctl enable --now avahi-daemon
systemctl enable sddm # No --now: aún estamos en TTY/script, no lanzar el display manager ahora

echo "✅ Servicios habilitados."

# -----------------------------
# 9. Instalar Zsh y Oh My Zsh
# -----------------------------
echo "🐚 Instalando Zsh y Oh My Zsh..."

pacman -S --noconfirm --needed \
  zsh \
  eza \
  zsh-autocomplete \
  zsh-autosuggestions \
  zsh-history-substring-search \
  zsh-syntax-highlighting

if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
  echo "👤 Instalando Oh My Zsh para $REAL_USER..."
  sudo -u "$REAL_USER" RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
else
  echo "⚠️ Oh My Zsh ya está instalado"
fi

# Copiar .zshrc desde respaldo si existe, si no usar el generado
ZSHRC_BACKUP="$USER_HOME/respaldo/.zshrc"
if [ -f "$ZSHRC_BACKUP" ]; then
  echo "📝 Copiando .zshrc desde respaldo..."
  cp "$ZSHRC_BACKUP" "$ZSHRC"
  echo "✅ .zshrc restaurado desde respaldo"
else
  echo "⚠️ No se encontró .zshrc en respaldo, se mantiene el generado por Oh My Zsh"
fi

# Dar permisos correctos al .zshrc
chown "$REAL_USER:$REAL_USER" "$ZSHRC"

# Cambiar shell a zsh
chsh -s /bin/zsh "$REAL_USER"
echo "✅ Shell cambiado a Zsh para $REAL_USER"

# -----------------------------
# 9.1. Configurar keyd
# -----------------------------
echo "⌨️  Configurando keyd..."

mkdir -p /etc/keyd

cat >/etc/keyd/default.conf <<'EOF'
# keyd config
# /etc/keyd/default.conf
[ids]
0461:4ec0:8e43ae64
[main]
mouse2 = M-f
[ids]
0fac:1ade:d2b36ae6
[main]
mouse1 = print
EOF

systemctl enable --now keyd
echo "✅ keyd configurado y habilitado."

# -----------------------------
# 10. Restaurar configuraciones desde respaldo
# -----------------------------
echo "📂 Restaurando configuraciones desde $USER_HOME/respaldo..."

BACKUP_DIR="$USER_HOME/respaldo"
CONFIG_DIR="$USER_HOME/.config"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "⚠️  No se encontró la carpeta $BACKUP_DIR — omitiendo restauración."
else
  mkdir -p "$CONFIG_DIR"

  for SRC in "$BACKUP_DIR"/*/; do
    [ -d "$SRC" ] || continue
    folder=$(basename "$SRC")

    # La carpeta scripts va a /usr/local/bin/, no a .config/
    if [ "$folder" = "scripts" ]; then
      echo "  📁 Copiando scripts → /usr/local/bin/"
      cp -r "$SRC"/. /usr/local/bin/
      chmod +x /usr/local/bin/*
      continue
    fi

    DEST="$CONFIG_DIR/$folder"
    echo "  📁 Copiando $folder → $CONFIG_DIR/"
    rm -rf "$DEST"
    cp -r "$SRC" "$DEST"
    chown -R "$REAL_USER:$REAL_USER" "$DEST"
  done

  # Restaurar config de howdy
  if [ -f "$BACKUP_DIR/howdy-config.ini" ]; then
    echo "  🔐 Restaurando configuración de howdy..."
    mkdir -p /etc/howdy
    cp "$BACKUP_DIR/howdy-config.ini" /etc/howdy/config.ini
    echo "  ✅ /etc/howdy/config.ini restaurado."
  else
    echo "  ⚠️  howdy-config.ini no encontrado en respaldo, omitiendo."
  fi

  # Restaurar archivos PAM con howdy
  restore_pam() {
    local src="$1"
    local dest="$2"
    if [ -f "$BACKUP_DIR/$src" ]; then
      echo "  🔐 Restaurando $dest..."
      cp "$BACKUP_DIR/$src" "$dest"
      echo "  ✅ $dest restaurado."
    else
      echo "  ⚠️  $src no encontrado en respaldo, omitiendo."
    fi
  }

  restore_pam "pam-sudo" "/etc/pam.d/sudo"
  restore_pam "pam-sddm" "/etc/pam.d/sddm"
  restore_pam "pam-polkit" "/etc/pam.d/polkit-gnome-authentication-agent-1"

  echo "✅ Configuraciones restauradas correctamente."
fi

# -----------------------------
# 11. Configurar Plymouth en mkinitcpio
# -----------------------------
echo "🎨 Configurando Plymouth en mkinitcpio..."

MKINITCPIO="/etc/mkinitcpio.conf"

# Agregar 'plymouth' después de 'udev' en los HOOKS si no está ya
if grep -q "plymouth" "$MKINITCPIO"; then
  echo "⚠️ Plymouth ya está en $MKINITCPIO"
else
  sed -i 's/\(HOOKS=.*udev\)/\1 plymouth/' "$MKINITCPIO"
  echo "✅ Plymouth agregado a los HOOKS de mkinitcpio"
fi

# Regenerar initramfs
echo "🔄 Regenerando initramfs..."
mkinitcpio -P
echo "✅ initramfs regenerado."

# -----------------------------
# 12. Notas post-instalación
# -----------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Instalación completada. Notas importantes:"
echo ""
echo "  🔵 Plymouth (splash de arranque):"
echo "     Ya se configuró en mkinitcpio automáticamente."
echo "     Aún debes agregar 'splash' a los parámetros del kernel"
echo "     según tu bootloader:"
echo "       systemd-boot → edita la entrada en /boot/loader/entries/*.conf"
echo "                       y agrega 'splash' en la línea 'options'"
echo "       GRUB         → edita /etc/default/grub, agrega 'splash'"
echo "                       en GRUB_CMDLINE_LINUX_DEFAULT y ejecuta:"
echo "                       grub-mkconfig -o /boot/grub/grub.cfg"
echo "       Limine       → edita limine.conf y agrega 'splash' en cmdline"
echo ""
echo "  🔵 Timeout del bootloader (1 segundo):"
echo "       systemd-boot → edita /boot/loader/loader.conf"
echo "                       y pon: timeout 1"
echo "       GRUB         → edita /etc/default/grub"
echo "                       y pon: GRUB_TIMEOUT=1"
echo "       Limine       → edita limine.conf y pon: timeout: 1"
echo ""
echo "  🔵 os-prober (arranque dual con GRUB):"
echo "     Edita /etc/default/grub y añade:"
echo "     GRUB_DISABLE_OS_PROBER=false"
echo "     Luego ejecuta: grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "  🔵 Snapper:"
echo "     Configura tus subvolúmenes con btrfs-assistant o manualmente:"
echo "     snapper -c root create-config /"
echo "     snapper -c home create-config /home"
echo ""
echo "  🔵 SDDM y SilentSDDM se activarán en el próximo arranque."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔁 Reiniciando en 10 segundos... (Ctrl+C para cancelar)"
sleep 10
reboot
