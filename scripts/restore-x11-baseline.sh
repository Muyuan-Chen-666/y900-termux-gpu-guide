#!/data/data/com.termux/files/usr/bin/bash
# Run in ordinary Termux, not inside Ubuntu. Installs files only; never starts/stops a desktop.
set -euo pipefail
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${PREFIX:?Run this script in Termux}"
ROOTFS="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs"
[[ -d "$ROOTFS/home/desktop" ]] || { echo '缺少现有 ubuntu 容器或 desktop 用户；先按 README 准备。'; exit 1; }
for name in python proot-distro termux-x11 virgl_test_server_android pulseaudio pactl; do
 command -v "$name" >/dev/null || { echo "缺少 Termux 依赖：$name"; exit 1; }
done
python - <<'PY'
from pathlib import Path
for p in Path('/proc').iterdir():
 if not p.name.isdigit():continue
 try:
  if (p/'comm').read_text().strip()=='xfce4-session':
   raise SystemExit('检测到 XFCE 正在运行。请保存工作并正常退出，再恢复脚本。')
 except OSError:pass
PY
proot-distro login ubuntu --user desktop --shared-tmp --no-sysvipc -- /bin/bash -c \
 'for c in xfce4-session xfconf-query dbus-run-session xdpyinfo glmark2 glxgears; do command -v "$c" >/dev/null || exit 1; done' \
 || { echo 'Ubuntu 依赖未就绪，未复制脚本。'; exit 1; }
BACKUP="$HOME/.local/share/y900-backup/archive-restore-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP/termux" "$BACKUP/ubuntu" "$BACKUP/config"
for src in "$BASE"/scripts/termux/*; do
 name=$(basename "$src")
 [[ ! -e "$PREFIX/bin/$name" ]] || cp -a "$PREFIX/bin/$name" "$BACKUP/termux/"
 install -m 755 "$src" "$PREFIX/bin/$name"
done
for src in "$BASE"/scripts/ubuntu/*; do
 name=$(basename "$src")
 [[ ! -e "$ROOTFS/usr/local/bin/$name" ]] || cp -a "$ROOTFS/usr/local/bin/$name" "$BACKUP/ubuntu/"
 install -m 755 "$src" "$ROOTFS/usr/local/bin/$name"
done
CONFIG="$ROOTFS/home/desktop/.config/y900-xfce-gpu/xfce4/xfconf/xfce-perchannel-xml"
[[ ! -d "$CONFIG" ]] || cp -a "$CONFIG" "$BACKUP/config/"
mkdir -p "$CONFIG"
for src in "$BASE"/config/xfconf/*.xml; do install -m 644 "$src" "$CONFIG/"; done
# start-tablet-gpu expects a base XFCE configuration directory even on a fresh image.
mkdir -p "$ROOTFS/home/desktop/.config/xfce4" "$HOME/xfce"
for action in start connect stop restart status logs; do
 [[ ! -f "$HOME/xfce/$action.sh" ]] || cp -a "$HOME/xfce/$action.sh" "$BACKUP/termux/xfce-$action.sh"
 printf '#!/data/data/com.termux/files/usr/bin/bash\nexec ubuntu-manager %s "$@"\n' "$action" > "$HOME/xfce/$action.sh"
 chmod 755 "$HOME/xfce/$action.sh"
done
printf '已恢复经验证的 X11/GPU 基线脚本，没有启动或停止桌面。\n旧文件备份：%s\n启动：ubuntu-manager start\n' "$BACKUP"
