#!/usr/bin/env bash
#
# gestionar-sddm.sh — Herramienta todo-en-uno para gestionar el tema SilentSDDM
#
# Subcomandos:
#   list                        Lista los presets disponibles en configs/
#   current                     Muestra el preset actualmente activo
#   set <preset>                Cambia el preset activo (ej: rei, ken, nord)
#   test [debug]                Prueba el tema sin reiniciar (./test.sh del tema)
#   update                      Reinstala/actualiza sddm-silent-theme vía paru
#   backup                      Guarda metadata.desktop actual en ~/respaldo/sddm/
#   avatar <usuario> <imagen> [tema]
#                                Cambia el avatar de un usuario. Si el tema no trae
#                                change_avatar.sh, usa AccountsService (genérico).
#   background <archivo> [login|lock|both] [tema]
#                                Cambia el fondo (imagen/video) del tema indicado
#                                (o el activo si se omite). Detecta automáticamente
#                                si el tema usa secciones [LoginScreen]/[LockScreen]
#                                (SilentSDDM) o claves planas *background* (otros temas).
#   pick | (sin argumentos)     Selector interactivo con fzf + preview (requiere chafa)
#                                ESC en la lista de archivos = volver al menú principal
#
#   themes                      Lista TODOS los temas SDDM instalados en /usr/share/sddm/themes
#   theme-current                Muestra el tema SDDM activo (independiente de SilentSDDM)
#   theme-set <nombre>           Activa un tema SDDM instalado (edita /etc/sddm.conf.d/*.conf)
#   config [tema]                Editor interactivo (fzf) de las opciones del theme.conf de
#                                 cualquier tema instalado (clock, colores, fuentes, etc).
#                                 Si no se indica tema, usa el activo.
#
# Requiere para el preview: chafa (sudo pacman -S chafa)
# Requiere para thumbnails de video: ffmpeg
#
# Uso: gestionar-sddm.sh <subcomando> [args]

set -e

green='\033[0;32m'
red='\033[0;31m'
bred='\033[1;31m'
cyan='\033[0;36m'
grey='\033[2;37m'
reset='\033[0m'

THEME_DIR="/usr/share/sddm/themes/silent"
BACKGROUNDS_DIR="$THEME_DIR/backgrounds"
VALID_BG_EXT="jpg|jpeg|png|avi|mp4|mov|mkv|m4v|webm"

# Carpetas de origen para el selector fzf
WALLPAPER_DIR="/home/jihey/Pictures/Wallpapers/dynamic-wallpaper"
AVATAR_DIR="/home/jihey/Pictures/avatar"

BACK_LABEL="⬅️  Volver al menú principal"

# Directorios de temas SDDM (genérico, no solo SilentSDDM)
SDDM_THEMES_DIR="/usr/share/sddm/themes"
SDDM_CONF_D="/etc/sddm.conf.d"
SDDM_CONF_FALLBACK="/etc/sddm.conf"

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_DIR="$USER_HOME/respaldo/sddm"
THUMB_CACHE="$USER_HOME/.cache/sddm-fzf-thumbs"

require_theme_installed() {
  if [[ ! -d "$THEME_DIR" ]]; then
    echo -e "${bred}❌ El tema SilentSDDM no está instalado en ${THEME_DIR}${reset}"
    echo -e "   Instálalo con: ${cyan}paru -S sddm-silent-theme${reset}"
    exit 1
  fi
}

get_active_conf_path() {
  local rel
  rel=$(awk -F '=' '/^ConfigFile=/ {print $2}' "$THEME_DIR/metadata.desktop")
  echo "$THEME_DIR/$rel"
}

set_conf_option() {
  local file="$1" section="$2" key="$3" value="$4"
  local tmp
  tmp=$(mktemp)

  sudo cat "$file" | awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section=0; found_section=0; replaced=0 }
    /^\[.*\]$/ {
      if (in_section && !replaced) {
        print key " = \"" value "\""
        replaced=1
      }
      cur = substr($0, 2, length($0)-2)
      in_section = (cur == section)
      if (in_section) found_section=1
      print
      next
    }
    {
      if (in_section && $0 ~ "^[ \t]*" key "[ \t]*=") {
        print key " = \"" value "\""
        replaced=1
        next
      }
      print
    }
    END {
      if (in_section && !replaced) {
        print key " = \"" value "\""
      }
      if (!found_section) {
        print ""
        print "[" section "]"
        print key " = \"" value "\""
      }
    }
  ' > "$tmp"

  sudo cp "$tmp" "$file"
  rm -f "$tmp"
}

# Igual que set_conf_option pero SIN comillas. El propio /etc/sddm.conf.d/*.conf
# (a diferencia de los configs/*.conf de SilentSDDM) no usa comillas: si se pone
# Current = "silent" con comillas, SDDM busca literalmente un tema llamado
# "silent" (comillas incluidas) y no lo encuentra.
set_conf_option_noquote() {
  local file="$1" section="$2" key="$3" value="$4"
  local tmp
  tmp=$(mktemp)

  sudo cat "$file" | awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section=0; found_section=0; replaced=0 }
    /^\[.*\]$/ {
      if (in_section && !replaced) {
        print key " = " value
        replaced=1
      }
      cur = substr($0, 2, length($0)-2)
      in_section = (cur == section)
      if (in_section) found_section=1
      print
      next
    }
    {
      if (in_section && $0 ~ "^[ \t]*" key "[ \t]*=") {
        print key " = " value
        replaced=1
        next
      }
      print
    }
    END {
      if (in_section && !replaced) {
        print key " = " value
      }
      if (!found_section) {
        print ""
        print "[" section "]"
        print key " = " value
      }
    }
  ' > "$tmp"

  sudo cp "$tmp" "$file"
  rm -f "$tmp"
}

# Igual que set_conf_option pero para archivos "planos" sin secciones [Section]
# (la mayoría de los theme.conf de temas SDDM normales son así: Key=Value o Key="Value")
set_flat_conf_option() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp=$(mktemp)

  if sudo grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sudo awk -v key="$key" -v value="$value" '
      {
        if ($0 ~ "^[ \t]*" key "[ \t]*=") {
          line=$0
          eqpos=index(line,"=")
          rest=substr(line, eqpos+1)
          gsub(/^[ \t]+/,"",rest)
          q=""
          if (substr(rest,1,1) == "\"") q="\""
          print key "=" q value q
        } else {
          print
        }
      }
    ' "$file" > "$tmp"
  else
    sudo cp "$file" "$tmp"
    echo "${key}=${value}" | sudo tee -a "$tmp" >/dev/null
  fi

  sudo cp "$tmp" "$file"
  rm -f "$tmp"
}

# Resuelve el archivo de configuración editable de un tema, sea estilo
# SilentSDDM (metadata.desktop -> ConfigFile=configs/x.conf) o un tema
# normal con theme.conf / theme.conf.user en la raíz.
resolve_theme_conf() {
  local tdir="$1"
  if [[ -f "$tdir/metadata.desktop" ]] && grep -q '^ConfigFile=' "$tdir/metadata.desktop" 2>/dev/null; then
    local rel
    rel=$(awk -F '=' '/^ConfigFile=/ {print $2}' "$tdir/metadata.desktop")
    if [[ -n "$rel" && -f "$tdir/$rel" ]]; then
      echo "$tdir/$rel"
      return
    fi
  fi
  if [[ -f "$tdir/theme.conf.user" ]]; then
    echo "$tdir/theme.conf.user"
  elif [[ -f "$tdir/theme.conf" ]]; then
    echo "$tdir/theme.conf"
  else
    echo ""
  fi
}

# Busca el tema activo respetando la precedencia REAL de SDDM:
# /etc/sddm.conf.d/*.conf (ordenados alfabéticamente, el ÚLTIMO que define
# [Theme] Current= gana) tiene prioridad sobre /etc/sddm.conf. Devuelve
# "nombre|archivo" del archivo que realmente manda.
find_active_theme() {
  local last_val="" last_file=""
  shopt -s nullglob
  for f in "$SDDM_CONF_D"/*.conf; do
    [[ -f "$f" ]] || continue
    local val
    val=$(awk '
      /^\[Theme\]/ { insec=1; next }
      /^\[.*\]/    { insec=0 }
      insec && /^[ \t]*Current[ \t]*=/ {
        sub(/^[ \t]*Current[ \t]*=[ \t]*/, "")
        gsub(/^"|"$/, "")
        gsub(/^[ \t]+|[ \t]+$/, "")
        print
        exit
      }
    ' "$f")
    if [[ -n "$val" ]]; then
      last_val="$val"
      last_file="$f"
    fi
  done
  shopt -u nullglob

  if [[ -n "$last_val" ]]; then
    echo "${last_val}|${last_file}"
    return
  fi

  if [[ -f "$SDDM_CONF_FALLBACK" ]]; then
    local val
    val=$(awk '
      /^\[Theme\]/ { insec=1; next }
      /^\[.*\]/    { insec=0 }
      insec && /^[ \t]*Current[ \t]*=/ {
        sub(/^[ \t]*Current[ \t]*=[ \t]*/, "")
        gsub(/^"|"$/, "")
        gsub(/^[ \t]+|[ \t]+$/, "")
        print
        exit
      }
    ' "$SDDM_CONF_FALLBACK")
    if [[ -n "$val" ]]; then
      echo "${val}|${SDDM_CONF_FALLBACK}"
      return
    fi
  fi
}

# Diagnóstico: lista TODOS los archivos (conf.d + sddm.conf) que definen
# [Theme] Current=, para detectar conflictos donde uno gana y otro queda
# ignorado silenciosamente.
diagnose_theme_conflicts() {
  local found=0
  shopt -s nullglob
  local f
  for f in "$SDDM_CONF_D"/*.conf "$SDDM_CONF_FALLBACK"; do
    [[ -f "$f" ]] || continue
    local val
    val=$(awk '
      /^\[Theme\]/ { insec=1; next }
      /^\[.*\]/    { insec=0 }
      insec && /^[ \t]*Current[ \t]*=/ {
        sub(/^[ \t]*Current[ \t]*=[ \t]*/, "")
        gsub(/^"|"$/, "")
        gsub(/^[ \t]+|[ \t]+$/, "")
        print
        exit
      }
    ' "$f")
    if [[ -n "$val" ]]; then
      echo -e "   ${grey}${f}${reset} -> Current = ${val}"
      found=$((found+1))
    fi
  done
  shopt -u nullglob
  if [[ "$found" -gt 1 ]]; then
    echo -e "${cyan}   ⚠️  Hay ${found} archivos definiendo el tema. Gana el ÚLTIMO listado arriba${reset}"
    echo -e "${cyan}      (orden alfabético de /etc/sddm.conf.d/, con prioridad sobre /etc/sddm.conf).${reset}"
  fi
}

cmd_themes() {
  if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
    echo -e "${bred}❌ No existe ${SDDM_THEMES_DIR}${reset}"
    exit 1
  fi
  local info active=""
  info=$(find_active_theme)
  [[ -n "$info" ]] && active="${info%%|*}"

  echo -e "${grey}Temas SDDM instalados en ${SDDM_THEMES_DIR}:${reset}"
  for d in "$SDDM_THEMES_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local name
    name=$(basename "$d")
    if [[ "$name" == "$active" ]]; then
      echo -e "  ${green}✔ ${name} (activo)${reset}"
    else
      echo -e "  • ${name}"
    fi
  done
}

cmd_theme_current() {
  local info
  info=$(find_active_theme)
  if [[ -z "$info" ]]; then
    echo -e "${red}❌ No se pudo determinar el tema activo (revisa ${SDDM_CONF_D}/*.conf)${reset}"
    exit 1
  fi
  echo -e "${green}Tema SDDM activo (el que realmente aplica):${reset} ${info%%|*} ${grey}(definido en ${info#*|})${reset}"
  echo -e "${grey}Archivos que definen [Theme] Current=:${reset}"
  diagnose_theme_conflicts
}

cmd_theme_set() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo -e "${red}❌ Debes indicar un tema. Ej: $0 theme-set pixel${reset}"
    cmd_themes
    exit 1
  fi
  if [[ ! -d "$SDDM_THEMES_DIR/$name" ]]; then
    echo -e "${red}❌ El tema '${name}' no está instalado en ${SDDM_THEMES_DIR}${reset}"
    cmd_themes
    exit 1
  fi

  local info target_file
  info=$(find_active_theme)
  target_file="${info#*|}"
  if [[ -z "$target_file" ]]; then
    target_file="$SDDM_CONF_D/10-theme.conf"
    sudo mkdir -p "$SDDM_CONF_D"
    sudo touch "$target_file"
  fi

  # Por si un valor anterior quedó con comillas (bug de versiones previas del
  # script), las limpiamos primero para no dejar basura tipo Current = ""silent""
  sudo sed -i -E 's/^([[:space:]]*Current[[:space:]]*=[[:space:]]*)"([^"]*)"[[:space:]]*$/\1\2/' "$target_file"

  set_conf_option_noquote "$target_file" "Theme" "Current" "$name"
  echo -e "${green}✅ Tema SDDM activo cambiado a: ${name}${reset} ${grey}(${target_file})${reset}"
  echo -e "${cyan}   Prueba con: sddm-greeter-qt6 --test-mode --theme ${SDDM_THEMES_DIR}/${name}${reset}"

  local recheck
  recheck=$(find_active_theme)
  if [[ "${recheck%%|*}" != "$name" ]]; then
    echo -e "${bred}⚠️  ADVERTENCIA: tras el cambio, el tema que realmente gana sigue siendo '${recheck%%|*}' (${recheck#*|}).${reset}"
    echo -e "${bred}   Hay otro archivo con MÁS prioridad definiendo el tema. Archivos en conflicto:${reset}"
    diagnose_theme_conflicts
  fi

  maybe_fix_virtual_keyboard "$name" "$target_file"
}

# InputMethod=qtvirtualkeyboard y QT_IM_MODULE=qtvirtualkeyboard (en
# GreeterEnvironment) son configs GLOBALES de sddm.conf, no por-tema.
# SilentSDDM las tolera bien porque maneja su propio teclado táctil, pero en
# cualquier otro tema disparan el teclado virtual genérico de Qt apenas el
# passwordBox recibe foco. Si el tema activo no es "silent" y detectamos esas
# líneas, ofrecemos quitarlas.
maybe_fix_virtual_keyboard() {
  local name="$1" file="$2"

  [[ "$name" == "silent" ]] && return

  local has_input_method has_im_module
  has_input_method=$(sudo grep -c '^[ \t]*InputMethod[ \t]*=[ \t]*qtvirtualkeyboard' "$file" 2>/dev/null || true)
  has_im_module=$(sudo grep -c 'QT_IM_MODULE=qtvirtualkeyboard' "$file" 2>/dev/null || true)

  if [[ "${has_input_method:-0}" -eq 0 && "${has_im_module:-0}" -eq 0 ]]; then
    return
  fi

  echo ""
  echo -e "${cyan}ℹ️  Detecté 'InputMethod=qtvirtualkeyboard' y/o 'QT_IM_MODULE=qtvirtualkeyboard' en ${file}.${reset}"
  echo -e "${cyan}   Esto es global (no por-tema) y en temas distintos a 'silent' suele abrir${reset}"
  echo -e "${cyan}   el teclado virtual genérico de Qt solo por enfocar el campo de contraseña.${reset}"
  read -r -p "¿Quitarlo para el tema '${name}'? [s/N]: " resp

  if [[ "$resp" =~ ^([sS]|[yY])$ ]]; then
    local tmp
    tmp=$(mktemp)
    sudo awk '
      /^[ \t]*InputMethod[ \t]*=[ \t]*qtvirtualkeyboard[ \t]*$/ { next }
      /^[ \t]*GreeterEnvironment[ \t]*=/ {
        line=$0
        gsub(/,?QT_IM_MODULE=qtvirtualkeyboard/, "", line)
        # Si GreeterEnvironment se quedó vacío (solo "GreeterEnvironment="), la omitimos
        if (line ~ /^[ \t]*GreeterEnvironment[ \t]*=[ \t]*$/) next
        print line
        next
      }
      { print }
    ' "$file" > "$tmp"
    sudo cp "$tmp" "$file"
    rm -f "$tmp"
    echo -e "${green}✅ Limpiado. El botón ⌨ manual del tema sigue funcionando igual.${reset}"
  else
    echo -e "${grey}Sin cambios. Puedes correrlo de nuevo con: $0 theme-set ${name}${reset}"
  fi
}

# Editor interactivo genérico de opciones de un theme.conf (o el config activo
# de SilentSDDM). Funciona con Key=Value planos y con archivos con [Secciones].
cmd_config() {
  local theme_name="$1"

  if [[ -z "$theme_name" ]]; then
    local info
    info=$(find_active_theme)
    theme_name="${info%%|*}"
  fi

  if [[ -z "$theme_name" ]]; then
    echo -e "${red}❌ No se pudo determinar el tema. Usa: $0 config <nombre-tema>${reset}"
    cmd_themes
    exit 1
  fi

  local tdir="$SDDM_THEMES_DIR/$theme_name"
  if [[ ! -d "$tdir" ]]; then
    echo -e "${red}❌ El tema '${theme_name}' no está instalado.${reset}"
    cmd_themes
    exit 1
  fi

  local conf
  conf=$(resolve_theme_conf "$tdir")
  if [[ -z "$conf" || ! -f "$conf" ]]; then
    echo -e "${red}❌ No se encontró un archivo de configuración editable para '${theme_name}'.${reset}"
    echo -e "   ${grey}(se buscó metadata.desktop/ConfigFile, theme.conf.user y theme.conf)${reset}"
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${red}❌ fzf no está instalado.${reset}"
    exit 1
  fi

  while true; do
    local entries
    entries=$(sudo awk '
      /^[ \t]*[;#]/ { next }
      /^[ \t]*\[.*\][ \t]*$/ {
        sec=$0
        gsub(/^[ \t]*\[|\][ \t]*$/, "", sec)
        next
      }
      /^[ \t]*[A-Za-z0-9_.]+[ \t]*=/ {
        line=$0
        sub(/^[ \t]+/, "", line)
        eqpos=index(line,"=")
        key=substr(line,1,eqpos-1)
        gsub(/[ \t]+$/, "", key)
        val=substr(line,eqpos+1)
        gsub(/^[ \t]+/, "", val)
        gsub(/^"|"$/, "", val)
        printf "%s\t%s\t%s\n", sec, key, val
      }
    ' "$conf")

    if [[ -z "$entries" ]]; then
      echo -e "${red}❌ No se detectaron opciones en ${conf}${reset}"
      break
    fi

    local chosen
    chosen=$(printf '%s\n' "$entries" | awk -F'\t' '{
        sec=($1==""?"(general)":"["$1"]")
        printf "%-16s %-28s = %s\n", sec, $2, $3
      }' | \
      fzf --prompt="Config [${theme_name}] > " --height=90% --border --reverse \
          --header="Enter = editar valor | Esc = salir | archivo: ${conf}" || true)

    [[ -z "$chosen" ]] && break

    local key sec oldval
    key=$(echo "$chosen" | awk '{print $2}')
    sec=$(printf '%s\n' "$entries" | awk -F'\t' -v k="$key" '$2==k{print $1; exit}')
    oldval=$(printf '%s\n' "$entries" | awk -F'\t' -v k="$key" '$2==k{print $3; exit}')

    echo -e "${cyan}Editando '${key}'${reset} ${grey}(valor actual: ${oldval})${reset}"
    read -r -p "Nuevo valor (Enter para cancelar): " newval
    [[ -z "$newval" ]] && continue

    if [[ -n "$sec" ]]; then
      set_conf_option "$conf" "$sec" "$key" "$newval"
    else
      set_flat_conf_option "$conf" "$key" "$newval"
    fi
    echo -e "${green}✅ ${key} = ${newval}${reset}"
  done
}

cmd_list() {
  require_theme_installed
  echo -e "${grey}Presets disponibles:${reset}"
  ls "$THEME_DIR/configs" | sed 's/\.conf$//' | sed 's/^/  • /'
}

cmd_current() {
  require_theme_installed
  current=$(awk -F '=' '/^ConfigFile=/ {print $2}' "$THEME_DIR/metadata.desktop" | sed 's|configs/||; s|\.conf$||')
  echo -e "${green}Preset activo:${reset} ${current}"
}

cmd_set() {
  require_theme_installed
  local preset="$1"

  if [[ -z "$preset" ]]; then
    echo -e "${red}❌ Debes indicar un preset. Ej: $0 set ken${reset}"
    cmd_list
    exit 1
  fi

  if [[ ! -f "$THEME_DIR/configs/${preset}.conf" ]]; then
    echo -e "${red}❌ El preset '${preset}' no existe.${reset}"
    cmd_list
    exit 1
  fi

  echo -e "${grey}Cambiando preset a '${preset}'...${reset}"
  sudo sed -i "s|^ConfigFile=.*|ConfigFile=configs/${preset}.conf|" "$THEME_DIR/metadata.desktop"
  echo -e "${green}✅ Preset cambiado a: ${preset}${reset}"
  echo -e "${cyan}   Prueba con: $0 test${reset}"
}

cmd_test() {
  require_theme_installed
  cd "$THEME_DIR"
  if [[ "$1" =~ ^(debug|-debug|--debug|-d)$ ]]; then
    sudo ./test.sh debug
  else
    echo -e "${grey}Probando tema (Ctrl+C para salir)...${reset}"
    sudo ./test.sh
  fi
}

cmd_update() {
  echo -e "${grey}Actualizando sddm-silent-theme vía paru...${reset}"
  sudo -u "$REAL_USER" paru -S --noconfirm sddm-silent-theme
  echo -e "${green}✅ Tema actualizado.${reset}"
}

cmd_backup() {
  require_theme_installed
  mkdir -p "$BACKUP_DIR"
  cp "$THEME_DIR/metadata.desktop" "$BACKUP_DIR/metadata.desktop"
  chown -R "$REAL_USER:$REAL_USER" "$BACKUP_DIR" 2>/dev/null || true
  echo -e "${green}✅ Backup de metadata.desktop guardado en ${BACKUP_DIR}${reset}"
}

cmd_avatar() {
  local username image theme_name

  if [[ $# -eq 1 ]]; then
    username="$REAL_USER"
    image="$1"
  elif [[ $# -eq 2 ]]; then
    username="$1"
    image="$2"
  elif [[ $# -eq 3 ]]; then
    username="$1"
    image="$2"
    theme_name="$3"
  else
    echo -e "${red}❌ Uso: $0 avatar [usuario] <ruta_imagen> [tema]${reset}"
    exit 1
  fi

  if [[ ! -f "$image" ]]; then
    echo -e "${red}❌ Archivo de imagen no encontrado: ${image}${reset}"
    exit 1
  fi

  if [[ -z "$theme_name" ]]; then
    local info
    info=$(find_active_theme)
    theme_name="${info%%|*}"
  fi
  [[ -z "$theme_name" ]] && theme_name="silent"

  local tdir="$SDDM_THEMES_DIR/$theme_name"

  # Estilo SilentSDDM: el propio tema trae su script para esto
  if [[ -x "$tdir/change_avatar.sh" ]]; then
    cd "$tdir"
    sudo ./change_avatar.sh "$username" "$image"
    return
  fi

  # Fallback genérico: la mayoría de temas SDDM modernos leen el avatar vía
  # AccountsService (icono independiente del tema), no del propio tema.
  echo -e "${grey}El tema '${theme_name}' no trae change_avatar.sh, usando AccountsService...${reset}"
  sudo mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users
  local icon_dest="/var/lib/AccountsService/icons/${username}"
  sudo cp -f "$image" "$icon_dest"
  sudo chmod 644 "$icon_dest"

  local user_conf="/var/lib/AccountsService/users/${username}"
  if [[ -f "$user_conf" ]]; then
    set_conf_option_noquote "$user_conf" "User" "Icon" "$icon_dest"
  else
    printf '[User]\nIcon=%s\n' "$icon_dest" | sudo tee "$user_conf" >/dev/null
  fi
  echo -e "${green}✅ Avatar actualizado vía AccountsService para '${username}'.${reset}"
}

cmd_background() {
  local src="$1"
  local target="${2:-both}"
  local theme_name="$3"

  if [[ -z "$src" ]]; then
    echo -e "${red}❌ Uso: $0 background <archivo> [login|lock|both] [tema]${reset}"
    exit 1
  fi

  if [[ ! -f "$src" ]]; then
    echo -e "${red}❌ Archivo no encontrado: ${src}${reset}"
    exit 1
  fi

  if [[ -z "$theme_name" ]]; then
    local info
    info=$(find_active_theme)
    theme_name="${info%%|*}"
  fi
  [[ -z "$theme_name" ]] && theme_name="silent"

  local tdir="$SDDM_THEMES_DIR/$theme_name"
  if [[ ! -d "$tdir" ]]; then
    echo -e "${red}❌ El tema '${theme_name}' no está instalado en ${SDDM_THEMES_DIR}${reset}"
    exit 1
  fi

  local ext="${src##*.}"
  ext="${ext,,}"
  if [[ ! "$ext" =~ ^(${VALID_BG_EXT})$ ]]; then
    echo -e "${red}❌ Formato no soportado: .${ext}${reset}"
    echo -e "   Soportados: jpg, jpeg, png, avi, mp4, mov, mkv, m4v, webm (NO .gif)"
    exit 1
  fi

  local filename
  filename=$(basename "$src")

  local conf
  conf=$(resolve_theme_conf "$tdir")
  if [[ -z "$conf" || ! -f "$conf" ]]; then
    echo -e "${red}❌ No se encontró un archivo de configuración editable para '${theme_name}'.${reset}"
    exit 1
  fi

  # Carpeta donde viven los assets del tema: reusamos backgrounds/ (estilo
  # SilentSDDM) o assets/ (estilo temas normales tipo 'sddm'/pixel) si ya
  # existen; si no hay ninguna, se copia a la raíz del tema.
  local assets_dir rel_path
  if [[ -d "$tdir/backgrounds" ]]; then
    assets_dir="$tdir/backgrounds"
    rel_path="backgrounds/$filename"
  elif [[ -d "$tdir/assets" ]]; then
    assets_dir="$tdir/assets"
    rel_path="assets/$filename"
  else
    assets_dir="$tdir"
    rel_path="$filename"
  fi

  echo -e "${grey}Copiando '${filename}' a ${assets_dir}/...${reset}"
  sudo mkdir -p "$assets_dir"
  sudo cp -f "$src" "$assets_dir/$filename"

  # Estilo SilentSDDM: secciones [LoginScreen] / [LockScreen] con clave "background"
  local has_login_section has_lock_section
  has_login_section=$(sudo grep -c '^\[LoginScreen\]' "$conf" 2>/dev/null || true)
  has_lock_section=$(sudo grep -c '^\[LockScreen\]' "$conf" 2>/dev/null || true)

  if [[ "${has_login_section:-0}" -gt 0 || "${has_lock_section:-0}" -gt 0 ]]; then
    if [[ "$target" == "login" || "$target" == "both" ]]; then
      set_conf_option "$conf" "LoginScreen" "background" "$rel_path"
      echo -e "${green}✅ Fondo de LoginScreen actualizado.${reset}"
    fi
    if [[ "$target" == "lock" || "$target" == "both" ]]; then
      set_conf_option "$conf" "LockScreen" "background" "$rel_path"
      echo -e "${green}✅ Fondo de LockScreen actualizado.${reset}"
    fi
  else
    # Estilo plano (theme.conf sin secciones): buscamos todas las claves que
    # contengan "background" en el nombre (background, defaultBackground, etc)
    # y las apuntamos al nuevo archivo.
    local bg_keys
    bg_keys=$(sudo grep -oE '^[[:space:]]*[A-Za-z0-9_.]*[Bb]ackground[A-Za-z0-9_.]*' "$conf" 2>/dev/null | sed 's/^[[:space:]]*//' | sort -u)

    if [[ -z "$bg_keys" ]]; then
      echo -e "${red}❌ No encontré ninguna clave tipo *background* en ${conf}.${reset}"
      echo -e "   ${grey}Revisa manualmente con: $0 config ${theme_name}${reset}"
      exit 1
    fi

    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      set_flat_conf_option "$conf" "$k" "$rel_path"
      echo -e "${green}✅ ${k} = ${rel_path}${reset}"
    done <<< "$bg_keys"
  fi

  if [[ "$ext" =~ ^(mp4|avi|mov|mkv|m4v|webm)$ ]]; then
    echo -e "${cyan}ℹ️  Es un video. Considera generar un placeholder con ffmpeg:${reset}"
    echo -e "   ${grey}ffmpeg -i \"$assets_dir/$filename\" -vframes 1 \"$assets_dir/${filename%.*}_placeholder.jpg\"${reset}"
  fi

  echo -e "${cyan}   Tema: ${theme_name} — prueba con: $0 config ${theme_name}${reset}"
}


# Genera el comando de preview para fzf usando chafa (funciona en cualquier shell/terminal
# que soporte color truecolor; en kitty además puede usar el protocolo de gráficos nativo).
# $1 = directorio base de los archivos listados (solo se muestran basenames en fzf)
build_preview_cmd() {
  local dir="$1"
  mkdir -p "$THUMB_CACHE"
  cat <<PREVIEW
sel={}
if [[ "\$sel" == "$BACK_LABEL" ]]; then
  echo "Volver al menú principal"
  exit 0
fi
f="$dir/\$sel"
ext="\${f##*.}"
ext=\$(printf '%s' "\$ext" | tr '[:upper:]' '[:lower:]')
if [[ "\$ext" = "mp4" || "\$ext" = "mov" || "\$ext" = "mkv" || "\$ext" = "m4v" || "\$ext" = "webm" || "\$ext" = "avi" ]]; then
  thumb="$THUMB_CACHE/\$sel.jpg"
  if [[ ! -f "\$thumb" ]] && command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -ss 00:00:01 -i "\$f" -vframes 1 -q:v 3 "\$thumb" >/dev/null 2>&1
  fi
  [[ -f "\$thumb" ]] && f="\$thumb"
fi
if command -v chafa >/dev/null 2>&1; then
  cols="\${FZF_PREVIEW_COLUMNS:-80}"
  lines="\${FZF_PREVIEW_LINES:-24}"
  chafa --size="\${cols}x\${lines}" "\$f"
else
  echo "chafa no está instalado (sudo pacman -S chafa)"
  echo ""
  file -b "\$f" 2>/dev/null
fi
PREVIEW
}

# Selector fzf para una carpeta de archivos (wallpapers o avatares).
# $2 = "wallpaper" (imagen o video) | "avatar" (solo imagen)
# Devuelve por stdout: nombre de archivo elegido, o "$BACK_LABEL", o vacío si se canceló.
select_file() {
  local dir="$1" filetype="$2" prompt="$3"
  local preview_cmd
  preview_cmd=$(build_preview_cmd "$dir")

  local files
  if [[ "$filetype" == "wallpaper" ]]; then
    files=$(find "$dir" -maxdepth 1 -type f \( \
        -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.m4v" \
        -o -iname "*.webm" -o -iname "*.avi" \
        -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
      \) -printf "%f\n" | sort)
  else
    files=$(find "$dir" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
      \) -printf "%f\n" | sort)
  fi

  { echo "$BACK_LABEL"; printf '%s\n' "$files"; } | \
    fzf --prompt="$prompt > " --height=90% --border --reverse \
        --header="ESC o '$BACK_LABEL' = volver" \
        --preview="$preview_cmd" --preview-window=right:60% || true
}

cmd_pick() {
  require_theme_installed

  if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${red}❌ fzf no está instalado.${reset}"
    exit 1
  fi

  if ! command -v chafa >/dev/null 2>&1; then
    echo -e "${cyan}ℹ️  chafa no está instalado, el preview de imágenes no funcionará.${reset}"
    echo -e "   Instálalo con: sudo pacman -S chafa"
  fi

  while true; do
    local choice
    choice=$(printf "🖼️  Wallpaper (fondo animado)\n👤  Avatar\n🎨  Elegir tema SDDM instalado\n⚙️  Editar configuración del tema\n🚪  Salir" | \
      fzf --prompt="¿Qué quieres cambiar? > " --height=10 --border --reverse || true)

    case "$choice" in
      *Wallpaper*)
        if [[ ! -d "$WALLPAPER_DIR" ]]; then
          echo -e "${red}❌ No existe la carpeta: $WALLPAPER_DIR${reset}"
          continue
        fi
        local file
        file=$(select_file "$WALLPAPER_DIR" "wallpaper" "Wallpaper")

        if [[ -z "$file" || "$file" == "$BACK_LABEL" ]]; then
          continue
        fi

        echo -e "${cyan}Aplicando wallpaper: ${file}...${reset}"
        cmd_background "$WALLPAPER_DIR/$file"
        echo -e "${green}✅ Listo.${reset}"
        read -n 1 -s -r -p "Presiona cualquier tecla para continuar..."
        ;;

      *Avatar*)
        if [[ ! -d "$AVATAR_DIR" ]]; then
          echo -e "${red}❌ No existe la carpeta: $AVATAR_DIR${reset}"
          continue
        fi
        local file
        file=$(select_file "$AVATAR_DIR" "avatar" "Avatar")

        if [[ -z "$file" || "$file" == "$BACK_LABEL" ]]; then
          continue
        fi

        echo -e "${cyan}Aplicando avatar: ${file}...${reset}"
        cmd_avatar "$AVATAR_DIR/$file"
        echo -e "${green}✅ Listo.${reset}"
        read -n 1 -s -r -p "Presiona cualquier tecla para continuar..."
        ;;

      *"tema SDDM instalado"*)
        if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
          echo -e "${red}❌ No existe: $SDDM_THEMES_DIR${reset}"
          continue
        fi
        local info active_name
        info=$(find_active_theme)
        active_name="${info%%|*}"

        local sel
        sel=$(for d in "$SDDM_THEMES_DIR"/*/; do
                [[ -d "$d" ]] || continue
                local n; n=$(basename "$d")
                if [[ "$n" == "$active_name" ]]; then echo "✔ $n (activo)"; else echo "  $n"; fi
              done | fzf --prompt="Tema SDDM > " --height=90% --border --reverse \
                          --header="Enter = activar | Esc = volver" || true)
        [[ -z "$sel" ]] && continue
        local theme_name
        theme_name=$(echo "$sel" | sed 's/^[✔ ]*//; s/ (activo)$//')
        cmd_theme_set "$theme_name"
        read -n 1 -s -r -p "Presiona cualquier tecla para continuar..."
        ;;

      *"configuración del tema"*)
        if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
          echo -e "${red}❌ No existe: $SDDM_THEMES_DIR${reset}"
          continue
        fi
        local info active_name
        info=$(find_active_theme)
        active_name="${info%%|*}"

        local sel
        sel=$(for d in "$SDDM_THEMES_DIR"/*/; do
                [[ -d "$d" ]] || continue
                basename "$d"
              done | fzf --prompt="Editar config de qué tema > " --height=90% --border --reverse \
                          --header="Tema activo actual: ${active_name:-desconocido}" || true)
        [[ -z "$sel" ]] && continue
        cmd_config "$sel"
        ;;

      *)
        # Salir, o ESC/cancelado en el menú principal
        break
        ;;
    esac
  done
}

case "$1" in
  list)       cmd_list ;;
  current)    cmd_current ;;
  set)        cmd_set "$2" ;;
  test)       cmd_test "$2" ;;
  update)     cmd_update ;;
  backup)     cmd_backup ;;
  avatar)     shift; cmd_avatar "$@" ;;
  background) shift; cmd_background "$@" ;;
  themes)         cmd_themes ;;
  theme-current)  cmd_theme_current ;;
  theme-set)      cmd_theme_set "$2" ;;
  config)         cmd_config "$2" ;;
  pick)       cmd_pick ;;
  "")         cmd_pick ;;
  *)
    echo -e "${cyan}Uso:${reset} $0 {list|current|set <preset>|test [debug]|update|backup|avatar [usuario] <imagen> [tema]|background <archivo> [login|lock|both] [tema]|themes|theme-current|theme-set <nombre>|config [tema]|pick}"
    exit 1
    ;;
esac
