# 📦 Instrucciones de respaldo para el instalador de Hyprland

El script busca una carpeta llamada `respaldo` en tu carpeta de usuario (`~/respaldo/`) y copia todo su contenido a `~/.config/`, sobreescribiendo lo que ya exista. Aquí te explico cómo preparar ese respaldo antes de ejecutar el instalador.

---

## 🗂️ Estructura esperada

```
~/respaldo/
├── .zshrc                  ← archivo, no carpeta
├── hypr/
├── kitty/
├── fastfetch/
├── nvim/
├── scripts/                ← va a /usr/local/bin/
├── howdy-config.ini        ← va a /etc/howdy/config.ini
├── pam-sudo                ← va a /etc/pam.d/sudo
├── pam-sddm                ← va a /etc/pam.d/sddm
├── pam-polkit              ← va a /etc/pam.d/polkit-gnome-authentication-agent-1
└── ... (cualquier otra carpeta de ~/.config/)
```

---

## ✅ Cómo guardar tus configuraciones actuales

Abre una terminal y ejecuta estos comandos:

### 1. Crear la carpeta de respaldo

```bash
mkdir -p ~/respaldo
```

### 2. Copiar configuraciones de ~/.config/

```bash
cp -r ~/.config/hypr          ~/respaldo/
cp -r ~/.config/kitty         ~/respaldo/
cp -r ~/.config/fastfetch     ~/respaldo/
cp -r ~/.config/nvim          ~/respaldo/
cp -r ~/.config/nvim-qt       ~/respaldo/
cp -r ~/.config/nwg-drawer    ~/respaldo/
cp -r ~/.config/nwg-look      ~/respaldo/
cp -r ~/.config/noctalia      ~/respaldo/
cp -r ~/.config/quickshell    ~/respaldo/
cp -r ~/.config/yazi          ~/respaldo/
cp -r ~/.config/MangoHud      ~/respaldo/
cp -r ~/.config/qt6ct         ~/respaldo/
```

O para copiar todo de una vez:

```bash
cp -r ~/.config/. ~/respaldo/
```

### 3. Copiar .zshrc

```bash
cp ~/.zshrc ~/respaldo/
```

### 4. Copiar scripts a /usr/local/bin/

```bash
mkdir -p ~/respaldo/scripts
cp /usr/local/bin/editconfig         ~/respaldo/scripts/
cp /usr/local/bin/update-system      ~/respaldo/scripts/
cp /usr/local/bin/snapper-boot-entries ~/respaldo/scripts/
```

### 5. Copiar configuración de howdy

```bash
sudo cp /etc/howdy/config.ini ~/respaldo/howdy-config.ini
```

> ⚠️ Los modelos de reconocimiento facial (`/etc/howdy/models/`) **no se respaldan** porque están vinculados al hardware de tu cámara. Tendrás que reentrenarlos con `howdy add` después de instalar.

### 6. Copiar archivos PAM de howdy

```bash
sudo cp /etc/pam.d/sudo   ~/respaldo/pam-sudo
sudo cp /etc/pam.d/sddm   ~/respaldo/pam-sddm
sudo cp /etc/pam.d/polkit-gnome-authentication-agent-1 ~/respaldo/pam-polkit
```

> ⚠️ Los archivos PAM son críticos. Si se corrompen puedes perder acceso a sudo. El script los restaura tal cual, así que asegúrate de que estén bien antes de respaldar.

### 7. Verificar que quedó bien

```bash
ls ~/respaldo/
```

Deberías ver algo así:

```
.zshrc  fastfetch  hypr  howdy-config.ini  kitty  MangoHud
noctalia  nvim  nvim-qt  nwg-drawer  nwg-look  pam-polkit
pam-sddm  pam-sudo  qt6ct  quickshell  scripts  yazi
```

---

## 🚀 Cómo usar el respaldo con el instalador

1. Coloca la carpeta `respaldo/` en la carpeta home del usuario (`~/respaldo/`)
2. Ejecuta el instalador normalmente:

```bash
sudo bash instalar_hyprland.sh
```

El script detecta automáticamente el usuario real (aunque se ejecute con `sudo`) y restaura las configuraciones en la ubicación correcta.

---

## 💡 Consejos

- Puedes comprimir el respaldo para guardarlo en un USB o compartirlo:
  ```bash
  tar -czf respaldo.tar.gz ~/respaldo/
  ```
- Para descomprimir en otra máquina antes de ejecutar el instalador:
  ```bash
  tar -xzf respaldo.tar.gz -C ~/
  ```
- El script **sobreescribe** el destino, así que no te preocupes si ya existe alguna carpeta en `~/.config/`.
