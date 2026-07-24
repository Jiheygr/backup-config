#!/usr/bin/env bash

set -e

# ==================================================================
#  script de instalación — Hyprland / Niri / KDE Plasma + apps y configs
#  Con TUI estilo "dank" usando gum (charmbracelet)
# ==================================================================

# -----------------------------
# 0. Parseo de argumentos
# -----------------------------
HYPRLAND_LUA_SRC=""
NIRI_KDL_SRC=""

usage() {
  cat <<EOF
Uso: sudo $(basename "$0") [opciones]

Opciones:
  --hyprland-lua <ruta>   Copia ese archivo como ~/.config/hypr/hyprland.lua
                          cuando se instale Hyprland "limpio" (sin respaldo)
  --niri-kdl <ruta>       Copia ese archivo como ~/.config/niri/config.kdl
                          cuando se instale Niri "limpio" (sin respaldo)
  -h, --help              Muestra esta ayuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --hyprland-lua)
    HYPRLAND_LUA_SRC="$2"
    shift 2
    ;;
  --niri-kdl)
    NIRI_KDL_SRC="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "❌ Opción desconocida: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ -n "$HYPRLAND_LUA_SRC" && ! -f "$HYPRLAND_LUA_SRC" ]]; then
  echo "❌ No se encontró el archivo indicado en --hyprland-lua: $HYPRLAND_LUA_SRC"
  exit 1
fi

if [[ -n "$NIRI_KDL_SRC" && ! -f "$NIRI_KDL_SRC" ]]; then
  echo "❌ No se encontró el archivo indicado en --niri-kdl: $NIRI_KDL_SRC"
  exit 1
fi

# -----------------------------
# 0.1. Verificar root
# -----------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script debe ejecutarse con sudo."
  exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
ZSHRC="$USER_HOME/.zshrc"

# Si vinieron con ruta relativa, resolverlas contra el directorio actual
if [[ -n "$HYPRLAND_LUA_SRC" ]]; then
  HYPRLAND_LUA_SRC="$(cd "$(dirname "$HYPRLAND_LUA_SRC")" && pwd)/$(basename "$HYPRLAND_LUA_SRC")"
fi
if [[ -n "$NIRI_KDL_SRC" ]]; then
  NIRI_KDL_SRC="$(cd "$(dirname "$NIRI_KDL_SRC")" && pwd)/$(basename "$NIRI_KDL_SRC")"
fi

# -----------------------------
# 0.1. Bootstrap de gum
# -----------------------------
if ! command -v gum &>/dev/null; then
  echo "📦 Instalando gum (TUI helper)..."
  pacman -S --noconfirm --needed gum >/dev/null 2>&1 || {
    echo "❌ No se pudo instalar gum. Revisa tu conexión o pacman.conf."
    exit 1
  }
fi

on_error() {
  local exit_code=$1
  local line_no=$2
  local failed_cmd=$3
  gum style --border rounded --border-foreground 196 --padding "1 3" --margin "1 0" \
    "❌ Falló un paso de la instalación" \
    "" \
    "Línea: $line_no" \
    "Comando: $failed_cmd" \
    "Código de salida: $exit_code" \
    "" \
    "Log completo: ${LOG_FILE:-"(aún no generado)"}"
  exit "$exit_code"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

export GUM_CHOOSE_CURSOR_FOREGROUND="25"
export GUM_CHOOSE_SELECTED_FOREGROUND="25"
export GUM_CONFIRM_PROMPT_FOREGROUND="25"
export GUM_SPIN_SPINNER_FOREGROUND="25"
export GUM_SPIN_SPINNER="dot"

banner() {
  gum style \
    --border rounded --border-foreground 25 \
    --padding "1 4" --margin "1 0" --align center \
    "🚀 Apps & Configuraciones Installer" "Chaotic-AUR · Noctalia · Dotfiles"
}

section() {
  gum style --foreground 25 --bold "▸ $1"
}

# -----------------------------
# Detección de consola básica (TTY sin terminal gráfica)
# -----------------------------
# En la consola cruda de Arch (antes de tener un WM/terminal gráfica) la
# fuente no tiene glifos para emoji ni para los bordes redondeados que usa
# gum, y su interfaz interactiva (bubbletea) puede directamente no
# renderizar bien ahí. Se detecta y se usa un menú numerado con `read`
# plano en su lugar, que siempre funciona en cualquier TTY.
IS_TTY_CONSOLE=false
[[ "$TERM" == "linux" ]] && IS_TTY_CONSOLE=true

# Saca los emoji conocidos que usa el script (lista fija, no rangos
# Unicode, para no depender de herramientas externas tipo perl/python).
strip_emoji() {
  sed -e 's/🔊//g; s/🤫//g; s/🌊//g; s/🌀//g; s/🔀//g; s/🟪//g; s/📦//g; s/✅//g; s/❌//g;
          s/🧹//g; s/📂//g; s/🎁//g; s/🔍//g; s/🖥️//g; s/📸//g; s/🎮//g;
          s/💬//g; s/🐚//g; s/🔐//g; s/🗂️//g; s/🎨//g; s/🐧//g; s/🔎//g' <<<"$1" |
    sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Selección de UNA opción. Usa gum en terminal gráfica, o un menú
# numerado con read en la consola básica.
ask_choice() {
  local header="$1"
  shift
  local opts=("$@")

  if ! $IS_TTY_CONSOLE; then
    gum choose --header "$header" "${opts[@]}"
    return
  fi

  {
    echo ""
    echo "== $(strip_emoji "$header") =="
    local i=1
    for o in "${opts[@]}"; do
      echo "  $i) $(strip_emoji "$o")"
      i=$((i + 1))
    done
  } >&2

  local n
  while true; do
    read -rp "Elegí un número [1-${#opts[@]}]: " n </dev/tty
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ]; then
      echo "${opts[$((n - 1))]}"
      return
    fi
    echo "Opción inválida." >&2
  done
}

# Selección MÚLTIPLE (todas premarcadas por defecto). Usa gum en
# terminal gráfica, o un menú numerado en la consola básica donde se
# escriben los números a DESMARCAR.
ask_multi() {
  local header="$1"
  shift
  local opts=("$@")

  if ! $IS_TTY_CONSOLE; then
    local joined
    joined=$(
      IFS=,
      echo "${opts[*]}"
    )
    gum choose --no-limit --selected "$joined" --header "$header" "${opts[@]}"
    return
  fi

  {
    echo ""
    echo "== $(strip_emoji "$header") =="
    local i=1
    for o in "${opts[@]}"; do
      echo "  $i) $o"
      i=$((i + 1))
    done
    echo "  Todas están premarcadas. Escribí los NÚMEROS a DESMARCAR"
    echo "  separados por espacio (Enter vacío = dejarlas todas)."
  } >&2

  local input
  read -rp "Desmarcar: " input </dev/tty

  local exclude=()
  read -ra exclude <<<"$input"

  local i=1
  for o in "${opts[@]}"; do
    local skip=false
    for x in "${exclude[@]}"; do
      [[ "$x" == "$i" ]] && skip=true
    done
    $skip || echo "$o"
    i=$((i + 1))
  done
}

# Confirmación sí/no. Usa gum en terminal gráfica, o [s/N] con read en
# la consola básica.
ask_confirm() {
  local question="$1"
  if ! $IS_TTY_CONSOLE; then
    gum confirm "$question"
    return
  fi
  local ans
  read -rp "$(strip_emoji "$question") [s/N]: " ans </dev/tty
  [[ "$ans" =~ ^[sSyY] ]]
}

# Entrada de texto libre (para resolución/refresh manual de monitor,
# por ejemplo). Usa "gum input" en terminal gráfica, o read en la
# consola básica.
ask_input() {
  local prompt="$1"
  local default="${2:-}"
  local ans
  if ! $IS_TTY_CONSOLE; then
    gum input --placeholder "$default" --prompt "$(strip_emoji "$prompt"): "
    return
  fi
  if [[ -n "$default" ]]; then
    read -rp "$(strip_emoji "$prompt") [$default]: " ans </dev/tty
    echo "${ans:-$default}"
  else
    read -rp "$(strip_emoji "$prompt"): " ans </dev/tty
    echo "$ans"
  fi
}

# -----------------------------
# Detección y selección de monitores vía EDID
# -----------------------------
# DETECTED_MONITORS: array de "conector|resolución|refresh|escala"
# (ej: "DP-1|2560x1440|144.00|1"). Se lee directo de /sys/class/drm, así
# que funciona aunque todavía no haya compositor corriendo.
DETECTED_MONITORS=()

detect_monitors() {
  section "🔎 Detectando monitores conectados..."
  pacman -Sy --noconfirm --needed edid-decode >/dev/null 2>&1 || true

  local edid_path
  for edid_path in /sys/class/drm/card*-*/edid; do
    [[ -s "$edid_path" ]] || continue

    local drm_path conn status info res refresh
    drm_path=$(dirname "$edid_path")
    conn=$(basename "$drm_path" | sed -E 's/^card[0-9]+-//') # DP-1, HDMI-A-1, eDP-1...
    status=$(cat "$drm_path/status" 2>/dev/null)
    [[ "$status" != "connected" ]] && continue

    info=$(edid-decode "$edid_path" 2>/dev/null)
    res=$(grep -A2 "Detailed Timing Descriptors" <<<"$info" | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -1)
    [[ -z "$res" ]] && res=$(grep -oE '[0-9]{3,4}x[0-9]{3,4}' <<<"$info" | sort -u | tail -1)
    refresh=$(grep -oE '[0-9]{2,3}\.[0-9]{2} Hz' <<<"$info" | sort -u | tail -1 | grep -oE '^[0-9.]+')

    if [[ -n "$res" ]]; then
      gum style --foreground 82 "  ✅ $conn detectado: ${res} @ ${refresh:-60.00}Hz"
      DETECTED_MONITORS+=("${conn}|${res}|${refresh:-60.00}|1")
    else
      gum style --foreground 244 "  ⚠️ $conn conectado pero no se pudo leer resolución del EDID"
      DETECTED_MONITORS+=("${conn}|||1")
    fi
  done

  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    gum style --foreground 196 "  ⚠️ No se detectó ningún monitor vía EDID — se usará auto-detect del compositor."
  fi
}

# Paso interactivo: para cada monitor detectado, preguntar si se usa lo
# detectado, se ingresa manualmente, o se deja en auto-detect (sin
# forzar nada). Modifica DETECTED_MONITORS in-place.
choose_monitor_settings() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    return
  fi

  section "🖥️  Configuración de monitor(es)"
  local i
  for i in "${!DETECTED_MONITORS[@]}"; do
    local conn res refresh scale
    IFS='|' read -r conn res refresh scale <<<"${DETECTED_MONITORS[$i]}"

    local detected_label
    if [[ -n "$res" ]]; then
      detected_label="✅ Usar lo detectado (${res}@${refresh}Hz)"
    else
      detected_label="✅ Usar lo detectado (no se pudo leer resolución)"
    fi

    local choice
    choice=$(ask_choice "Monitor ${conn} — ¿qué configuración querés usar?" \
      "$detected_label" \
      "✏️  Elegir resolución/refresh manualmente" \
      "🤖 Dejar en auto-detect (sin forzar nada)")

    case "$choice" in
    *"manualmente"*)
      local new_res new_refresh new_scale
      new_res=$(ask_input "Resolución para ${conn} (formato AnchoxAlto, ej: 1920x1080)" "$res")
      new_refresh=$(ask_input "Refresh rate para ${conn} en Hz (ej: 60.00)" "${refresh:-60.00}")
      new_scale=$(ask_input "Escala para ${conn} (ej: 1, 1.5, 2)" "${scale:-1}")
      DETECTED_MONITORS[$i]="${conn}|${new_res}|${new_refresh}|${new_scale}"
      gum style --foreground 82 "  ✅ ${conn} → ${new_res}@${new_refresh}Hz, escala ${new_scale}"
      ;;
    *"auto-detect"*)
      DETECTED_MONITORS[$i]="${conn}|||${scale:-1}"
      gum style --foreground 244 "  🤖 ${conn} → sin forzar (auto-detect del compositor)"
      ;;
    *)
      gum style --foreground 82 "  ✅ ${conn} → se usa lo detectado"
      ;;
    esac
  done
}

# Genera el bloque hl.monitor({...}) de Hyprland (sintaxis real del
# hyprland.lua) para cada monitor detectado, y lo devuelve por stdout
# (para reemplazar el marcador AUTO_MONITOR_BLOCK).
generate_hypr_monitor_block() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    cat <<'EOF'
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1.0,
})
EOF
    return
  fi
  local m conn res refresh scale
  for m in "${DETECTED_MONITORS[@]}"; do
    IFS='|' read -r conn res refresh scale <<<"$m"
    if [[ -n "$res" ]]; then
      cat <<EOF
hl.monitor({
	output = "${conn}",
	mode = "${res}@${refresh}",
	position = "auto",
	scale = ${scale:-1.0},
})
EOF
    else
      cat <<EOF
hl.monitor({
	output = "${conn}",
	mode = "preferred",
	position = "auto",
	scale = ${scale:-1.0},
})
EOF
    fi
  done
}

# Genera el/los bloque(s) "output" de Niri (sintaxis KDL) para el
# conector detectado y los devuelve por stdout (para reemplazar el
# marcador AUTO_MONITOR_BLOCK dentro del config.kdl).
generate_niri_output_block() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    echo "// No se detectó ningún monitor — usando auto-detect de niri por defecto"
    return
  fi
  local m conn res refresh scale
  for m in "${DETECTED_MONITORS[@]}"; do
    IFS='|' read -r conn res refresh scale <<<"$m"
    echo "output \"${conn}\" {"
    [[ -n "$res" ]] && echo "    mode \"${res}@${refresh}\""
    echo "    scale ${scale:-1}"
    echo "}"
  done
}

# -----------------------------
# 0.2. Selección de modo
# -----------------------------
clear
banner

MODE=$(ask_choice "Elige el modo de instalación:" \
  "🔊 Interactivo (sudo, con confirmaciones)" \
  "🤫 Silencioso (automático, sin pausas)")

case "$MODE" in
*Silencioso*) SILENT=true ;;
*) SILENT=false ;;
esac

LOG_FILE="/tmp/instalar_hyprland_$(date +%s).log"
: >"$LOG_FILE"

if $SILENT; then
  gum style --foreground 244 "Modo silencioso: sin pausas ni confirmaciones. Verás la salida de cada paso en pantalla y también en: $LOG_FILE"
else
  gum style --foreground 244 "Modo interactivo: se pedirá confirmación en pasos clave. Verás la salida de cada paso en pantalla y también en: $LOG_FILE"
fi
sleep 1

# -----------------------------
# 0.3. Selección de compositor
# -----------------------------
COMP=$(ask_choice "¿Qué querés instalar?" \
  "🌊 Hyprland (window manager + apps y configuraciones)" \
  "🌀 Niri (window manager + apps y configuraciones)" \
  "🔀 Ambos (Hyprland + Niri + apps y configuraciones)" \
  "🟪 KDE Plasma (escritorio completo)" \
  "📦 Solo apps y configuraciones (sin window manager)")

INSTALL_KDE=false
INSTALL_HYPRLAND=false
INSTALL_NIRI=false
case "$COMP" in
*Ambos*)
  INSTALL_HYPRLAND=true
  INSTALL_NIRI=true
  ;;
*Hyprland*)
  INSTALL_HYPRLAND=true
  INSTALL_NIRI=false
  ;;
*Niri*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=true
  ;;
*"KDE Plasma"*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=false
  INSTALL_KDE=true
  ;;
*"Solo apps"*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=false
  ;;
*)
  # No debería pasar nunca, pero si $COMP vino vacío o no matchea
  # ninguna opción, cortamos con un error BIEN visible (echo directo,
  # no solo gum) en vez de seguir en silencio con un valor por defecto
  # que puede confundir sobre qué se está instalando.
  echo "❌ No se reconoció la selección del window manager: '$COMP'" >&2
  echo "   Volvé a correr el script y probá de nuevo." >&2
  exit 1
  ;;
esac

if $INSTALL_KDE; then
  gum style --foreground 244 "Instalación de KDE Plasma, más apps y configuraciones."
elif $INSTALL_HYPRLAND && $INSTALL_NIRI; then
  gum style --foreground 244 "Instalación de window manager: Hyprland + Niri, más apps y configuraciones."
elif $INSTALL_HYPRLAND; then
  gum style --foreground 244 "Instalación de window manager: Hyprland, más apps y configuraciones."
elif $INSTALL_NIRI; then
  gum style --foreground 244 "Instalación de window manager: Niri, más apps y configuraciones."
else
  gum style --foreground 244 "Sin window manager — solo apps y configuraciones."
fi
sleep 1

# -----------------------------
# 0.4.1. Configuración de monitor(es) — paso obligatorio
# -----------------------------
# Se hace acá, antes de elegir apps (todo/por categorías), porque el
# monitor es parte de la config base del compositor, no una app extra.
if $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  detect_monitors
  choose_monitor_settings
fi

# -----------------------------
# 0.5. Noctalia Shell — automático con Hyprland/Niri (sin preguntar)
# -----------------------------
INSTALL_NOCTALIA=false
NOCTALIA_PKG=""
NOCTALIA_QS_PKG=""
RESTORE_NOCTALIA_CONFIG=false

if $INSTALL_KDE; then
  gum style --foreground 244 "Noctalia Shell es para Hyprland/Niri — se omite con KDE Plasma."
elif $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  INSTALL_NOCTALIA=true
  NOCTALIA_PKG="noctalia-git"
  NOCTALIA_QS_PKG="noctalia-qs-git"
  RESTORE_NOCTALIA_CONFIG=false
  gum style --foreground 244 "Noctalia Shell se instala automáticamente, limpio (elegiste Hyprland y/o Niri)."
fi

# -----------------------------
# 0.5.1. Selección de restauración de respaldo
# -----------------------------
RESTORE_HYPR_CONFIG=true
RESTORE_NIRI_CONFIG=true
RESTORE_KDE_CONFIG=false

if $INSTALL_KDE; then
  KDE_RESTORE_CHOICE=$(ask_choice "KDE Plasma: ¿limpio o restaurar desde respaldo/kde?" \
    "🧹 Limpio" \
    "📂 Restaurar respaldo/kde")
  case "$KDE_RESTORE_CHOICE" in
  *Restaurar*) RESTORE_KDE_CONFIG=true ;;
  *) RESTORE_KDE_CONFIG=false ;;
  esac
fi
# Hyprland y Niri restauran respaldo/hypr y respaldo/niri SIEMPRE, sin
# preguntar. Si además pasaste --hyprland-lua/--niri-kdl, esos flags no
# se aplican (ver sección 10.1 más abajo) porque el respaldo ya trae la
# config completa y no hay que pisarla.
# -----------------------------
# 0.8. Categorías de apps — una por una, con detección de instalado
# -----------------------------
# Todo lo que NO es estrictamente necesario para que el window manager
# elegido funcione (eso ya se instala aparte, fijo) se recorre categoría
# por categoría, cada una en su propia pantalla — sin un paso previo de
# "elegí qué categorías" que después se repite. Antes de cada categoría
# se avisa qué de eso ya está instalado.
INSTALL_ALL=false
ALL_OR_REVIEW=$(ask_choice "¿Cómo querés elegir las apps extra?" \
  "🎁 Instalar todo (sin revisar cada categoría)" \
  "🔍 Revisar categoría por categoría")
grep -q "Instalar todo" <<<"$ALL_OR_REVIEW" && INSTALL_ALL=true

INSTALL_CAT_PAMAC=false
INSTALL_CAT_HOWDY=false

# Muestra qué paquetes de una lista ya están instalados, si hay alguno.
show_already_installed() {
  local already=()
  for p in "$@"; do
    pacman -Qq "$p" &>/dev/null && already+=("$p")
  done
  if [[ ${#already[@]} -gt 0 ]]; then
    gum style --foreground 82 "  ✔ Ya instalado: $(
      IFS=', '
      echo "${already[*]}"
    )"
  fi
}

# Selecciona apps individuales dentro de una categoría. Recibe el
# título y la lista de paquetes; deja el resultado en SEL_RESULT.
pick_apps_in_category() {
  local title="$1"
  shift
  local all_pkgs=("$@")
  show_already_installed "${all_pkgs[@]}"
  # shellcheck disable=SC2207
  SEL_RESULT=($(ask_multi \
    "$title — desmarcá lo que NO quieras (espacio, enter para confirmar):" \
    "${all_pkgs[@]}"))
}

SEL_DESKTOP=()
SEL_CAPTURE=()
SEL_GAMING=()
SEL_APPS=()
SEL_TERMINAL=()
SEL_SNAPSHOTS=()

DESKTOP_ALL=(libappindicator-gtk3 nwg-drawer nwg-look papirus-icon-theme swaybg swaync
  thunar tumbler ffmpegthumbnailer wl-clip-persist wl-clipboard cliphist
  adw-gtk-theme qt6ct gsettings-qt6)
CAPTURE_ALL=(grim slurp gpu-screen-recorder cava mpvpaper)
GAMING_ALL=(wine-staging winetricks protontricks protonplus mangojuice steam gamemode gamescope vulkan-tools)
APPS_ALL=(telegram-desktop discord brave-origin-bin proton-vpn-gtk-app localsend
  mission-center fastfetch gnome-firmware gearlever chafa xarchiver)
TERMINAL_ALL=(neovim neovim-qt fzf jq eza yazi)
SNAPSHOTS_ALL=(btrfs-assistant btrfs-progs snapper snap-pac)

if $INSTALL_ALL; then
  INSTALL_CAT_PAMAC=true
  INSTALL_CAT_HOWDY=true
  SEL_DESKTOP=("${DESKTOP_ALL[@]}")
  SEL_CAPTURE=("${CAPTURE_ALL[@]}")
  SEL_GAMING=("${GAMING_ALL[@]}")
  SEL_APPS=("${APPS_ALL[@]}")
  SEL_TERMINAL=("${TERMINAL_ALL[@]}")
  SEL_SNAPSHOTS=("${SNAPSHOTS_ALL[@]}")
else
  # Gestor de paquetes gráfico (un solo paquete → sí/no, no picker)
  show_already_installed pamac-aur
  PAMAC_CHOICE=$(ask_choice "📦 ¿Instalar el gestor de paquetes gráfico (pamac)?" "✅ Sí" "❌ No")
  grep -q "Sí" <<<"$PAMAC_CHOICE" && INSTALL_CAT_PAMAC=true

  pick_apps_in_category "🖥️  Utilidades de escritorio" "${DESKTOP_ALL[@]}"
  SEL_DESKTOP=("${SEL_RESULT[@]}")

  pick_apps_in_category "📸 Capturas y grabación" "${CAPTURE_ALL[@]}"
  SEL_CAPTURE=("${SEL_RESULT[@]}")

  pick_apps_in_category "🎮 Gaming" "${GAMING_ALL[@]}"
  SEL_GAMING=("${SEL_RESULT[@]}")

  pick_apps_in_category "💬 Apps y comunicación" "${APPS_ALL[@]}"
  SEL_APPS=("${SEL_RESULT[@]}")

  pick_apps_in_category "🐚 Terminal avanzada" "${TERMINAL_ALL[@]}"
  SEL_TERMINAL=("${SEL_RESULT[@]}")

  # Autenticación facial (un solo paquete → sí/no, no picker)
  show_already_installed howdy-git
  HOWDY_CHOICE=$(ask_choice "🔐 ¿Instalar autenticación facial (howdy)?" "✅ Sí" "❌ No")
  grep -q "Sí" <<<"$HOWDY_CHOICE" && INSTALL_CAT_HOWDY=true

  pick_apps_in_category "🗂️  Snapshots BTRFS" "${SNAPSHOTS_ALL[@]}"
  SEL_SNAPSHOTS=("${SEL_RESULT[@]}")
fi

# Helpers de ejecución
# -----------------------------

run_step() {
  local desc="$1"
  shift
  section "$desc"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló: $desc" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi
}

confirm_step() {
  local question="$1"
  if $SILENT; then
    return 0
  fi
  ask_confirm "$question"
}

log_or_show() {
  if $SILENT; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    "$@"
  fi
}

# Instala una lista de paquetes con pacman mostrando una barra de progreso
# real con porcentaje (parseando las líneas "(n/total) installing ...").
# Toda la salida cruda igual queda guardada en $LOG_FILE por si falla algo.
run_pacman_progress() {
  local desc="$1"
  shift
  section "$desc"

  local tmp_out
  tmp_out=$(mktemp)
  local total_pkgs=$#

  # Antes usábamos stdbuf + captura por archivo normal, pero pacman
  # detecta que no hay una terminal real y deja de reescribir su barra
  # en vivo — solo imprime una línea por paquete cuando termina. Por eso
  # la barra "saltaba" en vez de ir fluida. Con `script` le damos una
  # pseudo-terminal real: pacman usa su barra nativa con \r y % interno
  # de cada paquete, y de ahí sacamos el progreso real.
  local pkg_args=()
  for p in "$@"; do pkg_args+=("$(printf '%q' "$p")"); done
  script -qefc "pacman -S --noconfirm --needed ${pkg_args[*]}" "$tmp_out" >/dev/null 2>&1 &
  local pid=$!

  local bar_len=30 cur=0 tot=$total_pkgs pkg="" pct=0 filled=0 last=""
  local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' spin_i=0 spin_phase_msg="" subpct=0

  while kill -0 "$pid" 2>/dev/null; do
    # El archivo tiene \r (actualizaciones en vivo) en vez de \n, y como
    # ahora pacman cree que tiene una terminal real, también mete
    # códigos de color ANSI antes de "(n/total)" — hay que sacarlos
    # antes de parsear, si no la línea no matchea y las variables
    # quedan vacías (causaba "printf: : invalid number").
    last=$(tr '\r' '\n' <"$tmp_out" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' |
      grep -E '\([0-9]+/[0-9]+\) (installing|upgrading|reinstalling)' | tail -1)
    if [[ -n "$last" ]]; then
      cur=$(grep -oE '^\([0-9]+' <<<"$last" | tr -d '(')
      tot=$(grep -oE '^\([0-9]+/[0-9]+\)' <<<"$last" | grep -oE '/[0-9]+' | tr -d '/')
      pkg=$(sed -E 's#^\([0-9]+/[0-9]+\) [a-z]+ ([^ ]+).*#\1#' <<<"$last")
      subpct=$(grep -oE '[0-9]+%' <<<"$last" | tail -1 | tr -d '%')
      # Blindaje: si por algún motivo alguna quedó vacía, usar 0 en vez
      # de dejar que printf reviente con "invalid number".
      [[ -z "$subpct" ]] && subpct=0
      [[ -z "$cur" ]] && cur=1
      [[ -z "$tot" || "$tot" -eq 0 ]] && tot=$total_pkgs
      [[ -z "$pkg" ]] && pkg="..."
      pct=$((((cur - 1) * 100 + subpct) / tot))
      [[ $pct -gt 100 ]] && pct=100
      [[ $pct -lt 0 ]] && pct=0
      filled=$((pct * bar_len / 100))
      printf "\r  \033[34m[%s%s]\033[0m %3d%%  (%d/%d) %-40s" \
        "$(printf '█%.0s' $(seq 1 "$filled" 2>/dev/null))" \
        "$(printf '░%.0s' $(seq 1 $((bar_len - filled)) 2>/dev/null))" \
        "$pct" "$cur" "$tot" "$pkg"
    else
      # Todavía no hay nada que contar — pacman sigue resolviendo
      # dependencias, sincronizando bases de datos o descargando.
      # Spinner para que se vea movimiento real desde el arranque.
      spin_phase_msg=$(tr '\r' '\n' <"$tmp_out" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tail -1 |
        grep -oE 'downloading\.\.\.|Synchronizing package databases\.\.\.|resolving dependencies\.\.\.|looking for conflicting packages\.\.\.|Retrieving packages\.\.\.' | tail -1)
      [[ -z "$spin_phase_msg" ]] && spin_phase_msg="preparando..."
      spin_i=$(((spin_i + 1) % ${#spin_chars}))
      printf "\r  \033[34m%s\033[0m %-50s" "${spin_chars:$spin_i:1}" "$spin_phase_msg"
    fi
    sleep 0.1
  done

  local rc=0
  wait "$pid" || rc=$?
  [[ -z "$tot" || "$tot" -eq 0 ]] && tot=$total_pkgs
  printf "\r  \033[34m[%s]\033[0m %3d%%  (%d/%d) %-40s\n" \
    "$(printf '█%.0s' $(seq 1 "$bar_len"))" 100 "$tot" "$tot" "listo"

  tr '\r' '\n' <"$tmp_out" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>"$LOG_FILE" 2>/dev/null

  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló: $desc" "Ver detalle en: $LOG_FILE"
    rm -f "$tmp_out"
    exit "$rc"
  fi

  rm -f "$tmp_out"
  gum style --foreground 82 "✅ $desc"
}

# -----------------------------
# 0.9. Resumen de lo que se va a instalar
# -----------------------------
SUMMARY_LINES=()

if $INSTALL_KDE; then
  SUMMARY_LINES+=("🟪 Escritorio: KDE Plasma")
  if $RESTORE_KDE_CONFIG; then
    SUMMARY_LINES+=("   • KDE: restaurar respaldo/kde")
  else
    SUMMARY_LINES+=("   • KDE: limpio")
  fi
elif $INSTALL_HYPRLAND && $INSTALL_NIRI; then
  SUMMARY_LINES+=("🌊🌀 Window manager: Hyprland + Niri")
elif $INSTALL_HYPRLAND; then
  SUMMARY_LINES+=("🌊 Window manager: Hyprland")
elif $INSTALL_NIRI; then
  SUMMARY_LINES+=("🌀 Window manager: Niri")
else
  SUMMARY_LINES+=("📦 Sin window manager (solo apps y configuraciones)")
fi

if $INSTALL_HYPRLAND; then
  if $RESTORE_HYPR_CONFIG; then
    SUMMARY_LINES+=("   • Hyprland: restaurar respaldo/hypr")
  elif [[ -n "$HYPRLAND_LUA_SRC" ]]; then
    SUMMARY_LINES+=("   • Hyprland: limpio, con hyprland.lua de --hyprland-lua")
  else
    SUMMARY_LINES+=("   • Hyprland: limpio (config de ejemplo del paquete)")
  fi
fi

if $INSTALL_NIRI; then
  if $RESTORE_NIRI_CONFIG; then
    SUMMARY_LINES+=("   • Niri: restaurar respaldo/niri")
  elif [[ -n "$NIRI_KDL_SRC" ]]; then
    SUMMARY_LINES+=("   • Niri: limpio, con config.kdl de --niri-kdl")
  else
    SUMMARY_LINES+=("   • Niri: limpio (config por defecto del paquete)")
  fi
fi

if $INSTALL_NOCTALIA; then
  SUMMARY_LINES+=("🎨 Noctalia Shell: sí ($NOCTALIA_PKG)")
  if $RESTORE_NOCTALIA_CONFIG; then
    SUMMARY_LINES+=("   • Noctalia: restaurar respaldo/noctalia")
  else
    SUMMARY_LINES+=("   • Noctalia: limpio (config por defecto)")
  fi
fi

SUMMARY_LINES+=("🔎 Hardware: CPU $CPU_VENDOR_ID (${CPU_UCODE_PKG:-sin microcode}) · GPU $GPU_VENDOR")

if $INSTALL_ALL; then
  SUMMARY_LINES+=("🎁 Apps: instalar todo (todas las categorías completas)")
else
  CAT_SUMMARY=()
  $INSTALL_CAT_PAMAC && CAT_SUMMARY+=("pamac")
  [[ ${#SEL_DESKTOP[@]} -gt 0 ]] && CAT_SUMMARY+=("escritorio (${#SEL_DESKTOP[@]})")
  [[ ${#SEL_CAPTURE[@]} -gt 0 ]] && CAT_SUMMARY+=("capturas (${#SEL_CAPTURE[@]})")
  [[ ${#SEL_GAMING[@]} -gt 0 ]] && CAT_SUMMARY+=("gaming (${#SEL_GAMING[@]})")
  [[ ${#SEL_APPS[@]} -gt 0 ]] && CAT_SUMMARY+=("apps/comunicación (${#SEL_APPS[@]})")
  [[ ${#SEL_TERMINAL[@]} -gt 0 ]] && CAT_SUMMARY+=("terminal (${#SEL_TERMINAL[@]})")
  $INSTALL_CAT_HOWDY && CAT_SUMMARY+=("howdy")
  [[ ${#SEL_SNAPSHOTS[@]} -gt 0 ]] && CAT_SUMMARY+=("snapshots (${#SEL_SNAPSHOTS[@]})")
  if [[ ${#CAT_SUMMARY[@]} -eq 0 ]]; then
    SUMMARY_LINES+=("📦 Apps: ninguna categoría extra elegida")
  else
    SUMMARY_LINES+=("📦 Apps: $(
      IFS=,
      echo "${CAT_SUMMARY[*]}"
    )")
  fi
fi

gum style --border rounded --border-foreground 25 --padding "1 3" --margin "1 0" \
  "📋 RESUMEN DE INSTALACIÓN" "" "${SUMMARY_LINES[@]}"

if ! $SILENT; then
  ask_confirm "¿Continuar con la instalación?" || {
    echo "Cancelado."
    exit 0
  }
fi

section "Iniciando la instalación de apps, configuraciones y el window manager seleccionado (si corresponde)..."

# -----------------------------
# 1. Importar las llaves GPG
# -----------------------------
run_step "🔑 Importando la llave de Chaotic-AUR..." bash -c 'pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && pacman-key --lsign-key 3056513887B78AEB'

# -----------------------------
# 2. Instalar Keyring y Mirrorlist
# -----------------------------
run_step "📥 Instalando chaotic-keyring y chaotic-mirrorlist..." pacman -U --noconfirm \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# -----------------------------
# 3. Añadir repo a pacman.conf
# -----------------------------
CONF="/etc/pacman.conf"
REPO="\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist"

if ! grep -q "\[chaotic-aur\]" "$CONF"; then
  if confirm_step "¿Añadir el repositorio [chaotic-aur] a $CONF?"; then
    echo -e "$REPO" >>"$CONF"
    section "✅ Repo añadido a pacman.conf"
  else
    gum style --foreground 196 "⏭️  Repo NO añadido (elegido por el usuario). El script puede fallar más adelante."
  fi
else
  gum style --foreground 244 "⚠️ Chaotic-AUR ya está en pacman.conf"
fi
# -----------------------------
# 4. Sincronizar y actualizar
# -----------------------------
run_step "🔄 Actualizando bases de datos y sistema..." pacman -Syyu --noconfirm

# -----------------------------
# 5. Instalar apps, configuraciones y el window manager seleccionado (si corresponde)
# -----------------------------
PACMAN_PKGS=(
  # Audio (PipeWire + WirePlumber, el stack estándar actual)
  pipewire
  pipewire-alsa
  pipewire-pulse
  pipewire-jack
  wireplumber
  # Básicos de escritorio (necesarios para cualquier sesión gráfica)
  kitty
  keyd
  brightnessctl
  pavucontrol
  xdg-desktop-portal
  polkit-gnome
  sddm
  xorg-server
  xorg-xhost
  xorg-xinit
  avahi
  firewalld
  plymouth
  os-prober
  imagemagick
  python
  git
  wget
  xdg-user-dirs
)

if $INSTALL_HYPRLAND; then
  PACMAN_PKGS+=(
    hyprcursor
    hyprgraphics
    hypridle
    hyprland
    hyprland-guiutils
    hyprland-protocols
    hyprland-qt-support
    hyprlang
    hyprsunset
    xdg-desktop-portal-hyprland
  )
fi

if $INSTALL_NIRI; then
  PACMAN_PKGS+=(
    niri
    xwayland-satellite
    xdg-desktop-portal-gnome
  )
fi

if $INSTALL_KDE; then
  PACMAN_PKGS+=(
    plasma-desktop
    plasma-nm
    plasma-pa
    plasma-systemmonitor
    kscreen
    powerdevil
    sddm-kcm
    dolphin
    konsole
    kate
    spectacle
    xdg-desktop-portal-kde
    print-manager
  )
fi

$INSTALL_CAT_PAMAC && PACMAN_PKGS+=(pamac)

[[ ${#SEL_DESKTOP[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_DESKTOP[@]}")
[[ ${#SEL_CAPTURE[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_CAPTURE[@]}")
[[ ${#SEL_GAMING[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_GAMING[@]}")
[[ ${#SEL_APPS[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_APPS[@]}")
[[ ${#SEL_TERMINAL[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_TERMINAL[@]}")

$INSTALL_CAT_HOWDY && PACMAN_PKGS+=(howdy-git)

[[ ${#SEL_SNAPSHOTS[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_SNAPSHOTS[@]}")

run_pacman_progress "🖥️ Instalando apps, configuraciones y utilidades (${#PACMAN_PKGS[@]} paquetes)..." \
  "${PACMAN_PKGS[@]}"

gum style --foreground 82 "✅ Paquetes instalados correctamente."

# -----------------------------
# 5.1. Configurar Snapper automáticamente (BTRFS)
# -----------------------------
# Solo tiene sentido si se eligió instalar snapper y el filesystem raíz
# es BTRFS (create-config falla si no lo es).
SNAPPER_CONFIGURED=false
if command -v snapper &>/dev/null; then
  ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null)
  if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    section "🗂️  Configurando Snapper..."

    if [ ! -f /etc/snapper/configs/root ]; then
      snapper -c root create-config / >>"$LOG_FILE" 2>&1
      gum style --foreground 82 "✅ Config 'root' de snapper creada."
    else
      gum style --foreground 244 "⚠️ Config 'root' de snapper ya existía, se ajustan sus valores."
    fi

    # Ajusta los valores conocidos sin pisar el resto del archivo (que
    # create-config ya llena con comentarios/defaults del paquete).
    apply_snapper_setting() {
      local file="$1" key="$2" value="$3"
      if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$file"
      else
        echo "${key}=\"${value}\"" >>"$file"
      fi
    }

    SNAPPER_ROOT_CONF="/etc/snapper/configs/root"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "SPACE_LIMIT" "0.5"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "FREE_LIMIT" "0.2"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "SYNC_ACL" "no"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "BACKGROUND_COMPARISON" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_MIN_AGE" "3600"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_LIMIT" "30"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_LIMIT_IMPORTANT" "10"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_CREATE" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_MIN_AGE" "3600"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_HOURLY" "8"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_DAILY" "7"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_WEEKLY" "4"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_MONTHLY" "3"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_QUARTERLY" "0"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_YEARLY" "0"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "EMPTY_PRE_POST_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "EMPTY_PRE_POST_MIN_AGE" "3600"

    # /home solo si es su propio subvolumen BTRFS (si comparte el mismo
    # subvolumen que /, snapper create-config para home fallaría o
    # duplicaría snapshots innecesariamente).
    HOME_FSTYPE=$(findmnt -n -o FSTYPE /home 2>/dev/null)
    if [[ "$HOME_FSTYPE" == "btrfs" ]] && [ ! -f /etc/snapper/configs/home ]; then
      snapper -c home create-config /home >>"$LOG_FILE" 2>&1
      gum style --foreground 82 "✅ Config 'home' de snapper creada (con los defaults del paquete)."
    fi

    log_or_show systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || true
    SNAPPER_CONFIGURED=true
    gum style --foreground 82 "✅ Snapper configurado y timers habilitados."
  else
    gum style --foreground 244 "⚠️ Filesystem raíz no es BTRFS ($ROOT_FSTYPE) — se omite configuración de Snapper."
  fi
fi

# -----------------------------
# 6. Función auxiliar para instalar paquetes AUR sin helper
# -----------------------------
run_step "📦 Instalando base-devel y git..." pacman -S --noconfirm --needed base-devel git

SUDOERS_TMP="/etc/sudoers.d/99-aur-install"
echo "$REAL_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"

install_aur_manual() {
  local aur_url="$1"
  local pkg_name="$2"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  chown "$REAL_USER:$REAL_USER" "$tmp_dir"

  local script
  script="sudo -u '$REAL_USER' git clone '$aur_url' '$tmp_dir/$pkg_name' && sudo -u '$REAL_USER' bash -c \"cd '$tmp_dir/$pkg_name' && makepkg -si --noconfirm\""

  section "📦 Instalando $pkg_name desde AUR (sin helper)..."
  bash -c "$script" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló instalando $pkg_name" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi

  rm -rf "$tmp_dir"
  gum style --foreground 82 "✅ $pkg_name instalado correctamente."
}

# -----------------------------
# 6.2. Noctalia Shell — opcional (estable o git, según lo elegido)
# -----------------------------
# noctalia/noctalia-git dependen de noctalia-qs/noctalia-qs-git, que
# también son paquetes AUR (no están en los repos oficiales). makepkg -si
# por sí solo NO resuelve dependencias AUR-sobre-AUR, así que hay que
# construirlos manualmente primero, sin importar qué helper se haya
# elegido arriba.
if $INSTALL_NOCTALIA; then
  install_aur_manual "https://aur.archlinux.org/${NOCTALIA_QS_PKG}.git" "$NOCTALIA_QS_PKG"
  install_aur_manual "https://aur.archlinux.org/${NOCTALIA_PKG}.git" "$NOCTALIA_PKG"

  if ! $RESTORE_NOCTALIA_CONFIG; then
    # Limpio: config por defecto (respaldo/noctalia, si se pidió, se
    # restaura más adelante en el paso de restauración de respaldo).
    NOCTALIA_CONFIG_DIR="$USER_HOME/.config/noctalia"
    mkdir -p "$NOCTALIA_CONFIG_DIR"
    if [ -f "$NOCTALIA_CONFIG_DIR/config.toml" ]; then
      gum style --foreground 244 "⚠️ Ya existe $NOCTALIA_CONFIG_DIR/config.toml — no se sobrescribe."
    else
      cat >"$NOCTALIA_CONFIG_DIR/config.toml" <<'EOF'
[theme]
mode              = "dark"        # dark | light | auto
source            = "builtin"     # builtin | wallpaper | community | custom
builtin           = "Noctalia"    # bundled palette name
EOF
      chown -R "$REAL_USER:$REAL_USER" "$NOCTALIA_CONFIG_DIR"
      gum style --foreground 82 "✅ $NOCTALIA_CONFIG_DIR/config.toml creado (limpio)."
    fi
  fi
fi

# -----------------------------
# 7. Instalar tema SilentSDDM
# -----------------------------
section "🎨 Instalando tema SilentSDDM..."

OTHER_DMS=(gdm lightdm ly lxdm xdm entrance nodm)
for dm in "${OTHER_DMS[@]}"; do
  if systemctl is-enabled "$dm" &>/dev/null; then
    if confirm_step "Display manager '$dm' detectado y activo. ¿Deshabilitarlo?"; then
      systemctl disable "$dm" >>"$LOG_FILE" 2>&1 || true
      gum style --foreground 82 "✅ $dm deshabilitado."
    else
      gum style --foreground 196 "⏭️  $dm NO deshabilitado. Puede haber conflicto con SDDM."
    fi
  fi
done

run_step "📥 Instalando dependencias del tema (qt6-svg, qt6-virtualkeyboard, qt6-multimedia-ffmpeg)..." \
  pacman -S --noconfirm --needed qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg

install_aur_manual "https://aur.archlinux.org/redhat-fonts.git" "redhat-fonts"
install_aur_manual "https://aur.archlinux.org/sddm-silent-theme.git" "sddm-silent-theme"

# -----------------------------
# 7.2. HyprMod / NiriMod (GUIs para editar la config de Hyprland/Niri)
# -----------------------------
# Ambos son apps GTK4/libadwaita en desarrollo activo, no empaquetadas en
# los repos oficiales todavía. hyprmod sí está en el AUR (paquete normal);
# nirimod solo existe como nirimod-git.
if $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  run_step "📥 Instalando dependencias de HyprMod/NiriMod (GTK4, libadwaita)..." \
    pacman -S --noconfirm --needed gtk4 libadwaita python-gobject python-cairo
fi

if $INSTALL_HYPRLAND; then
  # hyprmod depende de 5 paquetes que TAMBIÉN son solo-AUR
  # (python-hyprland-config/monitors/schema/socket/state). makepkg -si
  # no resuelve dependencias AUR-sobre-AUR solo — por eso fallaba con
  # "no puede resolver dependencias". Hay que construirlos manualmente
  # primero, en orden (los de más bajo nivel primero).
  install_aur_manual "https://aur.archlinux.org/python-hyprland-schema.git" "python-hyprland-schema"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-socket.git" "python-hyprland-socket"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-state.git" "python-hyprland-state"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-monitors.git" "python-hyprland-monitors"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-config.git" "python-hyprland-config"
  install_aur_manual "https://aur.archlinux.org/hyprmod.git" "hyprmod"
fi

if $INSTALL_NIRI; then
  install_aur_manual "https://aur.archlinux.org/nirimod-git.git" "nirimod-git"
fi

SDDM_CONF="/etc/sddm.conf"

cat >"$SDDM_CONF" <<'EOF'
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=silent
EOF

gum style --foreground 82 "✅ Tema SilentSDDM instalado y configurado."

rm -f "$SUDOERS_TMP"
gum style --foreground 244 "🔒 Regla temporal de sudoers eliminada."

# -----------------------------
# 7.1. Configurar portal XDG para niri
# -----------------------------
# Niri no trae su propio backend de portal (a diferencia de Hyprland con
# xdg-desktop-portal-hyprland). Le indicamos que use el backend de GNOME
# solo cuando la sesión activa sea "niri" (XDG_CURRENT_DESKTOP=niri),
# así no interfiere con el portal que ya usa Hyprland.
if $INSTALL_NIRI; then
  section "🌀 Configurando xdg-desktop-portal para la sesión de niri..."

  NIRI_PORTAL_DIR="$USER_HOME/.config/xdg-desktop-portal"
  mkdir -p "$NIRI_PORTAL_DIR"

  cat >"$NIRI_PORTAL_DIR/niri-portals.conf" <<'EOF'
[preferred]
default=gnome
org.freedesktop.impl.portal.Access=gnome
org.freedesktop.impl.portal.FileChooser=gnome
org.freedesktop.impl.portal.Screenshot=gnome
org.freedesktop.impl.portal.Screencast=gnome
EOF

  chown -R "$REAL_USER:$REAL_USER" "$NIRI_PORTAL_DIR"
  gum style --foreground 82 "✅ $NIRI_PORTAL_DIR/niri-portals.conf creado."
fi

# -----------------------------
# 8. Habilitar servicios
# -----------------------------
section "🔥 Habilitando servicios del sistema..."

log_or_show systemctl enable --now firewalld
log_or_show systemctl enable --now avahi-daemon
log_or_show systemctl enable sddm

if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --add-port=53317/udp --permanent &>/dev/null
  firewall-cmd --reload &>/dev/null
fi

if command -v ufw &>/dev/null; then
  ufw allow 53317/udp &>/dev/null
fi

# Audio (PipeWire suele activarse solo por socket activation al
# instalarse, pero lo forzamos para no depender de que el preset ande)
sudo -u "$REAL_USER" systemctl --user enable --now pipewire pipewire-pulse wireplumber &>/dev/null || true

if $INSTALL_HYPRLAND; then
  sudo -u "$REAL_USER" systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service &>/dev/null || true
fi

gum style --foreground 82 "✅ Servicios habilitados."

# -----------------------------
# 9. Instalar Zsh y Oh My Zsh
# -----------------------------
run_pacman_progress "🐚 Instalando Zsh y plugins..." \
  zsh eza zsh-autocomplete zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting

if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
  ohmyzsh_script="sudo -u '$REAL_USER' RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)\""
  section "👤 Instalando Oh My Zsh para $REAL_USER..."
  bash -c "$ohmyzsh_script" 2>&1 | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló instalando Oh My Zsh" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi
else
  gum style --foreground 244 "⚠️ Oh My Zsh ya está instalado"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC_BACKUP="$SCRIPT_DIR/respaldo/.zshrc"

if [ -f "$ZSHRC_BACKUP" ]; then
  cp "$ZSHRC_BACKUP" "$ZSHRC"
  gum style --foreground 82 "✅ .zshrc restaurado desde respaldo"
else
  gum style --foreground 244 "⚠️ No se encontró .zshrc en respaldo — generando uno por defecto (no depende del repo)"

  # $ZSHRC en este punto es el generado por el instalador de Oh My Zsh.
  # Ajustamos tema y plugins ahí mismo (sed) en vez de pisar todo el
  # archivo, para no perder lo que Oh My Zsh ya dejó configurado.
  if [ -f "$ZSHRC" ]; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="geoffgarside"/' "$ZSHRC"
    sed -i 's/^plugins=(.*/plugins=(git sudo)/' "$ZSHRC"
  fi

  CUSTOM_BLOCK_MARK="### CUSTOM PLUGINS ###"
  if ! grep -qF "$CUSTOM_BLOCK_MARK" "$ZSHRC" 2>/dev/null; then
    cat >>"$ZSHRC" <<'EOF'

# Preferred editor for local and remote sessions
export EDITOR=nvim

### CUSTOM PLUGINS ###
source /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

# Better ls
alias ls='eza -a --icons=always'
alias y='yazi'
alias icat="kitten icat"
alias svim='sudo nvim "+set number"'
### END CUSTOM PLUGINS ###

export QT_QPA_PLATFORMTHEME=qt6ct

# apps
fastfetch
EOF
    gum style --foreground 82 "✅ .zshrc por defecto generado (tema, plugins, alias svim y más)"
  else
    gum style --foreground 244 "⚠️ El bloque custom ya existía en .zshrc, no se duplicó"
  fi
fi

chown "$REAL_USER:$REAL_USER" "$ZSHRC"
chsh -s /bin/zsh "$REAL_USER"
gum style --foreground 82 "✅ Shell cambiado a Zsh para $REAL_USER"

# -----------------------------
# 9.1. Configurar keyd
# -----------------------------
section "⌨️  Configurando keyd..."

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

log_or_show systemctl enable --now keyd
gum style --foreground 82 "✅ keyd configurado y habilitado."

# -----------------------------
# 10. Restaurar configuraciones desde respaldo
# -----------------------------
section "📂 Restaurando configuraciones desde $SCRIPT_DIR/respaldo..."

# Generar las carpetas de usuario estándar (Pictures, Videos, Documents,
# etc.) ANTES de restaurar — así "Pictures" existe en el idioma/nombre
# correcto y no queda mal puesta o duplicada.
sudo -u "$REAL_USER" xdg-user-dirs-update &>/dev/null || true

BACKUP_DIR="$SCRIPT_DIR/respaldo"
CONFIG_DIR="$USER_HOME/.config"

if [ ! -d "$BACKUP_DIR" ]; then
  gum style --foreground 244 "⚠️  No se encontró la carpeta $BACKUP_DIR — omitiendo restauración."
else
  mkdir -p "$CONFIG_DIR"

  for SRC in "$BACKUP_DIR"/*/; do
    [ -d "$SRC" ] || continue
    folder=$(basename "$SRC")

    if [ "$folder" = "scripts" ]; then
      cp -r "$SRC"/. /usr/local/bin/
      chmod +x /usr/local/bin/*
      gum style --foreground 82 "  ✅ scripts → /usr/local/bin/"

      # Si snapper quedó configurado y el script de entradas de boot
      # está entre los que se acaban de copiar, armamos el hook de
      # pacman para que se regeneren solas en cada transacción.
      if $SNAPPER_CONFIGURED && command -v arch-snapper-boot-entries &>/dev/null; then
        SNAPPER_HOOK_DIR="/etc/pacman.d/hooks"
        mkdir -p "$SNAPPER_HOOK_DIR"
        cat >"$SNAPPER_HOOK_DIR/95-snapper-boot-entries.hook" <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Actualizando entradas de arranque de snapshots (snapper)...
When = PostTransaction
Exec = /usr/bin/env bash -c 'command -v arch-snapper-boot-entries >/dev/null && arch-snapper-boot-entries || true'
EOF
        gum style --foreground 82 "  ✅ Hook de pacman creado: las entradas de boot se regeneran solas en cada transacción."
      elif $SNAPPER_CONFIGURED; then
        gum style --foreground 244 "  ⚠️ Snapper está configurado pero no se encontró arch-snapper-boot-entries en /usr/local/bin — revisá que esté en respaldo/scripts/."
      fi

      continue
    fi

    # Carpeta de imágenes/wallpapers: va a la carpeta REAL de Imágenes
    # del usuario (respetando xdg-user-dirs, con fallback a ~/Pictures),
    # no a ~/.config — así sirve para wallpapers y fotos, no configs.
    case "$folder" in
    Pictures | pictures | Imagenes | imagenes | Imágenes | wallpapers | Wallpapers)
      PICTURES_DIR=$(sudo -u "$REAL_USER" xdg-user-dir PICTURES 2>/dev/null)
      [ -z "$PICTURES_DIR" ] && PICTURES_DIR="$USER_HOME/Pictures"
      mkdir -p "$PICTURES_DIR"
      cp -r "$SRC"/. "$PICTURES_DIR"/
      chown -R "$REAL_USER:$REAL_USER" "$PICTURES_DIR"
      gum style --foreground 82 "  ✅ $folder → $PICTURES_DIR/ (wallpapers y fotos)"
      continue
      ;;
    esac

    # Carpeta especial: unidades systemd de usuario (services/timers),
    # que NO van a ~/.config/<folder> tal cual sino a
    # ~/.config/systemd/user/, y además hay que habilitarlas.
    if [ "$folder" = "systemd-user" ]; then
      USER_SYSTEMD_DIR="$CONFIG_DIR/systemd/user"
      sudo -u "$REAL_USER" mkdir -p "$USER_SYSTEMD_DIR"
      cp "$SRC"/. "$USER_SYSTEMD_DIR"/ -r 2>/dev/null
      shopt -s nullglob
      cp "$SRC"*.service "$SRC"*.timer "$USER_SYSTEMD_DIR"/ 2>/dev/null || true
      shopt -u nullglob
      chown -R "$REAL_USER:$REAL_USER" "$USER_SYSTEMD_DIR"
      gum style --foreground 82 "  ✅ systemd-user → $USER_SYSTEMD_DIR/"

      sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
        systemctl --user daemon-reload || true

      shopt -s nullglob
      for timer_file in "$USER_SYSTEMD_DIR"/*.timer; do
        timer_name=$(basename "$timer_file")
        sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
          systemctl --user enable --now "$timer_name" &&
          gum style --foreground 82 "  ✅ $timer_name activado." ||
          gum style --foreground 244 "  ⚠️  No se pudo activar $timer_name."
      done
      shopt -u nullglob
      continue
    fi

    # Respetar qué se eligió instalar. Antes esto solo miraba
    # RESTORE_*_CONFIG (limpio/respaldo), pero eso ya no alcanza: si no
    # elegiste ese compositor, su carpeta de respaldo no debe copiarse
    # NUNCA, sin importar el valor de RESTORE_*_CONFIG.
    if [ "$folder" = "hypr" ] && ! $INSTALL_HYPRLAND; then
      gum style --foreground 244 "  ⏭️  hypr → omitido (no elegiste instalar Hyprland)"
      continue
    fi
    if [ "$folder" = "niri" ] && ! $INSTALL_NIRI; then
      gum style --foreground 244 "  ⏭️  niri → omitido (no elegiste instalar Niri)"
      continue
    fi
    if [ "$folder" = "kde" ] && ! $INSTALL_KDE; then
      gum style --foreground 244 "  ⏭️  kde → omitido (no elegiste instalar KDE)"
      continue
    fi
    if [ "$folder" = "noctalia" ] && ! $INSTALL_NOCTALIA; then
      gum style --foreground 244 "  ⏭️  noctalia → omitido (Noctalia no se instaló)"
      continue
    fi

    if [ "$folder" = "hypr" ] && ! $RESTORE_HYPR_CONFIG; then
      gum style --foreground 244 "  ⏭️  hypr → omitido (se pidió Hyprland limpio)"
      continue
    fi
    if [ "$folder" = "niri" ] && ! $RESTORE_NIRI_CONFIG; then
      gum style --foreground 244 "  ⏭️  niri → omitido (se pidió Niri limpio)"
      continue
    fi
    if [ "$folder" = "noctalia" ] && ! $RESTORE_NOCTALIA_CONFIG; then
      gum style --foreground 244 "  ⏭️  noctalia → omitido (se pidió Noctalia limpio)"
      continue
    fi
    if [ "$folder" = "kde" ] && ! $RESTORE_KDE_CONFIG; then
      gum style --foreground 244 "  ⏭️  kde → omitido (se pidió KDE limpio)"
      continue
    fi

    DEST="$CONFIG_DIR/$folder"
    rm -rf "$DEST"
    cp -r "$SRC" "$DEST"

    # Si el archivo restaurado tiene el marcador AUTO_MONITOR_BLOCK
    # (hyprland.lua o config.kdl), lo reemplazamos acá con el monitor
    # que se detectó/eligió al principio del script. Esto corre siempre
    # (no solo en instalación limpia) porque el respaldo se restaura
    # siempre por defecto.
    if [ "$folder" = "hypr" ] && [ -f "$DEST/hyprland.lua" ] && grep -q "AUTO_MONITOR_BLOCK" "$DEST/hyprland.lua"; then
      HYPR_MONITOR_BLOCK=$(generate_hypr_monitor_block)
      awk -v block="$HYPR_MONITOR_BLOCK" '
        /AUTO_MONITOR_BLOCK/ { print block; next }
        { print }
      ' "$DEST/hyprland.lua" >"$DEST/hyprland.lua.tmp"
      mv "$DEST/hyprland.lua.tmp" "$DEST/hyprland.lua"
      gum style --foreground 82 "  ✅ Monitor(es) aplicado(s) a $DEST/hyprland.lua"
    fi
    if [ "$folder" = "niri" ] && [ -f "$DEST/config.kdl" ] && grep -q "AUTO_MONITOR_BLOCK" "$DEST/config.kdl"; then
      NIRI_MONITOR_BLOCK=$(generate_niri_output_block)
      awk -v block="$NIRI_MONITOR_BLOCK" '
        /AUTO_MONITOR_BLOCK/ { print block; next }
        { print }
      ' "$DEST/config.kdl" >"$DEST/config.kdl.tmp"
      mv "$DEST/config.kdl.tmp" "$DEST/config.kdl"
      gum style --foreground 82 "  ✅ Monitor(es) aplicado(s) a $DEST/config.kdl"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$DEST"
    gum style --foreground 82 "  ✅ $folder → $CONFIG_DIR/"
  done

  if [ -f "$BACKUP_DIR/howdy-config.ini" ]; then
    mkdir -p /etc/howdy
    cp "$BACKUP_DIR/howdy-config.ini" /etc/howdy/config.ini
    gum style --foreground 82 "  ✅ /etc/howdy/config.ini restaurado."
  else
    gum style --foreground 244 "  ⚠️  howdy-config.ini no encontrado en respaldo, omitiendo."
  fi

  restore_pam() {
    local src="$1"
    local dest="$2"
    if [ -f "$BACKUP_DIR/$src" ]; then
      cp "$BACKUP_DIR/$src" "$dest"
      gum style --foreground 82 "  ✅ $dest restaurado."
    else
      gum style --foreground 244 "  ⚠️  $src no encontrado en respaldo, omitiendo."
    fi
  }

  restore_pam "pam-sudo" "/etc/pam.d/sudo"
  restore_pam "pam-sddm" "/etc/pam.d/sddm"
  restore_pam "pam-polkit" "/etc/pam.d/polkit-gnome-authentication-agent-1"

  gum style --foreground 82 "✅ Configuraciones restauradas correctamente."
fi

# -----------------------------
# 10.1. Aplicar hyprland.lua / niri config.kdl — SOLO en instalación
#       limpia (sin respaldo). Si se restauró respaldo/hypr o
#       respaldo/niri, esos dotfiles ya son la config completa y esto
#       no debe pisarlos.
# -----------------------------
if $INSTALL_HYPRLAND && ! $RESTORE_HYPR_CONFIG; then
  HYPR_DEST_DIR="$CONFIG_DIR/hypr"
  mkdir -p "$HYPR_DEST_DIR"
  if [[ -n "$HYPRLAND_LUA_SRC" ]]; then
    section "🌙 Instalación limpia de Hyprland: aplicando hyprland.lua provisto por --hyprland-lua..."
    cp "$HYPRLAND_LUA_SRC" "$HYPR_DEST_DIR/hyprland.lua"

    if grep -q "AUTO_MONITOR_BLOCK" "$HYPR_DEST_DIR/hyprland.lua"; then
      HYPR_MONITOR_BLOCK=$(generate_hypr_monitor_block)
      awk -v block="$HYPR_MONITOR_BLOCK" '
        /AUTO_MONITOR_BLOCK/ { print block; next }
        { print }
      ' "$HYPR_DEST_DIR/hyprland.lua" >"$HYPR_DEST_DIR/hyprland.lua.tmp"
      mv "$HYPR_DEST_DIR/hyprland.lua.tmp" "$HYPR_DEST_DIR/hyprland.lua"
      gum style --foreground 82 "✅ Monitor(es) detectado(s) agregado(s) a $HYPR_DEST_DIR/hyprland.lua"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$HYPR_DEST_DIR"
    gum style --foreground 82 "✅ $HYPR_DEST_DIR/hyprland.lua actualizado desde $HYPRLAND_LUA_SRC"
  else
    gum style --foreground 244 "⚠️  Hyprland limpio sin --hyprland-lua — se usa la config de ejemplo que trae el paquete."
  fi
elif [[ -n "$HYPRLAND_LUA_SRC" ]]; then
  gum style --foreground 244 "⚠️  Se pasó --hyprland-lua pero se restauró respaldo/hypr — se omite para no pisarlo."
fi

if $INSTALL_NIRI && ! $RESTORE_NIRI_CONFIG; then
  if [[ -n "$NIRI_KDL_SRC" ]]; then
    section "🌙 Instalación limpia de Niri: aplicando config.kdl provisto por --niri-kdl..."
    NIRI_DEST_DIR="$CONFIG_DIR/niri"
    mkdir -p "$NIRI_DEST_DIR"
    cp "$NIRI_KDL_SRC" "$NIRI_DEST_DIR/config.kdl"

    if grep -q "AUTO_MONITOR_BLOCK" "$NIRI_DEST_DIR/config.kdl"; then
      NIRI_MONITOR_BLOCK=$(generate_niri_output_block)
      # Reemplaza la línea del marcador por el bloque generado.
      # Se usa un archivo temporal porque el bloque puede tener varias
      # líneas (varios monitores), lo cual sed -i no maneja bien inline.
      awk -v block="$NIRI_MONITOR_BLOCK" '
        /AUTO_MONITOR_BLOCK/ { print block; next }
        { print }
      ' "$NIRI_DEST_DIR/config.kdl" >"$NIRI_DEST_DIR/config.kdl.tmp"
      mv "$NIRI_DEST_DIR/config.kdl.tmp" "$NIRI_DEST_DIR/config.kdl"
      gum style --foreground 82 "✅ Monitor(es) detectado(s) agregado(s) a $NIRI_DEST_DIR/config.kdl"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$NIRI_DEST_DIR"
    gum style --foreground 82 "✅ $NIRI_DEST_DIR/config.kdl actualizado desde $NIRI_KDL_SRC"
  else
    gum style --foreground 244 "⚠️  Niri limpio sin --niri-kdl — se usa la config por defecto que trae el paquete."
  fi
elif [[ -n "$NIRI_KDL_SRC" ]]; then
  gum style --foreground 244 "⚠️  Se pasó --niri-kdl pero se restauró respaldo/niri — se omite para no pisarlo."
fi

# -----------------------------
# 11. Configurar Plymouth en mkinitcpio
# -----------------------------
section "🎨 Configurando Plymouth en mkinitcpio..."

MKINITCPIO="/etc/mkinitcpio.conf"

if grep -q "plymouth" "$MKINITCPIO"; then
  gum style --foreground 244 "⚠️ Plymouth ya está en $MKINITCPIO"
else
  sed -i 's/\(HOOKS=.*udev\)/\1 plymouth/' "$MKINITCPIO"
  gum style --foreground 82 "✅ Plymouth agregado a los HOOKS de mkinitcpio"
fi

# -----------------------------
# 12. Notas post-instalación
# -----------------------------
gum style --border rounded --border-foreground 25 --padding "1 3" --margin "1 0" "$(
  cat <<'EOF'
🎉 Instalación completada. Notas importantes:

🔵 Plymouth (splash de arranque):
   Configurado automáticamente: hook en mkinitcpio, 'splash' en
   /etc/kernel/cmdline (embebido en el UKI) y timeout de systemd-boot
   en 1 segundo. No hace falta tocar nada más.

🔵 os-prober (arranque dual con GRUB, si aplica):
   /etc/default/grub → GRUB_DISABLE_OS_PROBER=false
   Luego: grub-mkconfig -o /boot/grub/grub.cfg

🔵 Snapper:
   Configurado automáticamente si el filesystem raíz es BTRFS (config
   'root' con tus valores, timers de timeline/cleanup habilitados). No
   hace falta correrlo a mano.

🔵 SDDM y SilentSDDM se activarán en el próximo arranque.
EOF
)"

if $SILENT; then
  gum style --foreground 244 "🔁 Reiniciando en 10 segundos... (Ctrl+C para cancelar)"
  sleep 10
  reboot
else
  if confirm_step "¿Reiniciar el sistema ahora?"; then
    reboot
  else
    gum style --foreground 244 "Reinicio pospuesto. Ejecuta 'reboot' cuando quieras aplicar todos los cambios."
  fi
fi
