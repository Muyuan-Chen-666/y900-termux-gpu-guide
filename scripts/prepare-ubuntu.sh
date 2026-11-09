#!/bin/bash
# Optional fresh-image helper. Run as the simulated root inside Ubuntu, passing the actual Termux UID.
set -euo pipefail
: "${Y900_UID:?Pass the actual Termux UID from outside the container}"
[[ "$Y900_UID" =~ ^[0-9]+$ && "$Y900_UID" -gt 0 ]] || { echo 'Invalid UID'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends xfce4 xfce4-terminal dbus-x11 \
 x11-utils x11-xserver-utils mesa-utils glmark2-x11 libgl1-mesa-dri \
 fonts-noto-cjk fonts-noto-color-emoji locales ca-certificates \
 fcitx5 fcitx5-chinese-addons adwaita-icon-theme
if id desktop >/dev/null 2>&1; then
 [[ $(id -u desktop) == "$Y900_UID" && $(id -g desktop) == "$Y900_UID" ]] || {
  echo '现有 desktop 的 UID/GID 与 Termux 不同；停止，未自动修改用户身份。'; exit 1;
 }
else
 if ! getent group "$Y900_UID" >/dev/null; then groupadd -g "$Y900_UID" desktop; fi
 useradd -m -u "$Y900_UID" -g "$Y900_UID" -s /bin/bash desktop
fi
locale-gen zh_CN.UTF-8 en_US.UTF-8
install -d -o desktop -g "$(id -gn desktop)" /home/desktop/.config/xfce4 /home/desktop/.config/autostart
cat > /home/desktop/.config/autostart/fcitx5.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5
OnlyShowIn=XFCE;
DESKTOP
chown desktop:"$(id -gn desktop)" /home/desktop/.config/autostart/fcitx5.desktop
printf 'Ubuntu 图形依赖已准备。退出后在普通 Termux 运行 restore-x11-baseline.sh。\n'
