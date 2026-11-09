#!/data/data/com.termux/files/usr/bin/bash
# Ordinary Termux. Requires an already-running baseline desktop; does not install/start anything.
set -euo pipefail
case ${1:-smoke} in
 smoke)
  exec ubuntu-manager run timeout --kill-after=3s 45s glmark2 --size 800x600 \
   --benchmark build:duration=5 --benchmark texture:duration=5 --benchmark shading:duration=5
  ;;
 gears)
  # Interactive window: close it to end; Ctrl+C also ends the foreground process.
  exec ubuntu-manager run glxgears -info -geometry 800x600
  ;;
 compare)
  ubuntu-manager software timeout --kill-after=3s 45s glmark2 --size 800x600 \
   --benchmark build:duration=5 --benchmark texture:duration=5 --benchmark shading:duration=5
  exec ubuntu-manager run timeout --kill-after=3s 45s glmark2 --size 800x600 \
   --benchmark build:duration=5 --benchmark texture:duration=5 --benchmark shading:duration=5
  ;;
 *) echo '用法：bash scripts/run-gpu-test.sh smoke|gears|compare'; exit 1 ;;
esac
