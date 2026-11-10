# Termux + PRoot 常用指令表

> 基于 **2026-11-10 实机**（联想 Y900 / Termux Play 分支 / proot-distro 5.8.0 / Termux:X11 1.03.01）校对。
> 容器名 `ubuntu`，容器用户 `desktop`；Termux 用户以 `whoami` 为准（归档中用 `u0_aXXX` 代替）。
> 文中 `y900 ...` 是新增的短命令入口，等价于对应的 `ubuntu-manager ...`，底层行为不变。

## 0. 一页速查

| 想做什么 | 输入 |
|---|---|
| 启动 GPU 桌面 | `y900 start` |
| 停止桌面 | `y900 stop` |
| 重启桌面 | `y900 restart` |
| 看是否在运行 | `y900 status` |
| 打开/切到 X11 窗口 | `y900 open` |
| 跑 glmark2 验收 | `y900 test` |
| 跑 glxgears 目视确认 | `y900 gears` |
| 进入容器（管理员） | `y900 shell` |
| 进入容器（图形终端） | `y900 desk` |
| 看日志 | `y900 logs` |
| 改 X11 分辨率 | `y900 size 1600x1067` |
| 检查依赖 | `y900 check` |

> 停止或重启前，先在桌面里保存工作。`y900 stop` 会同时停止桌面、Termux:X11 与 VirGL 服务。

## 1. 连接与登录

在平板本地：直接打开 Termux 输入命令即可。

从电脑连接平板（USB ADB + SSH）：

```bash
# 电脑端：把平板 8022 转到本机 18022
adb forward tcp:18022 tcp:8022

# 电脑端：用已授权的密钥登录
ssh -p 18022 -i ~/.ssh/y900_termux u0_aXXX@127.0.0.1
```

| 用途 | 命令 |
|---|---|
| 确认当前用户 | `whoami` / `id` |
| 查看 Termux 版本与环境 | `termux-info` |
| 防止息屏后进程被挂起 | `termux-wake-lock` |
| 释放唤醒锁 | `termux-wake-unlock` |
| 首次授权共享存储 | `termux-setup-storage` |
| 查看 ADB 连接（电脑端） | `adb devices` |

## 2. Termux 包管理

| 用途 | 命令 |
|---|---|
| 更新索引 | `pkg update` |
| 升级已装包 | `pkg upgrade` |
| 安装 | `pkg install <包名>` |
| 搜索 | `pkg search <关键字>` |
| 查包内文件 | `pkg files <包名>` |
| 列出已安装 | `pkg list-installed` |

> 本机 `PREFIX=/data/data/com.termux/files/usr`。不要卸载 Termux，也不要套用其他发行版的目录布局。

## 3. 容器（proot-distro 5.8.0）

| 用途 | 命令 |
|---|---|
| 列出容器 | `proot-distro list`（**输出在 stderr**，管道时写 `2>&1`） |
| 进入容器（管理员） | `y900 shell` |
| 进入容器（`desktop` 用户） | `proot-distro login ubuntu --user desktop --shared-tmp --no-sysvipc -- /bin/bash` |
| 一次性执行命令 | `proot-distro login ubuntu --shared-tmp --no-sysvipc -- bash -lc '命令'` |
| 查看活动会话 | `proot-distro ps` |
| 结束某容器全部会话 | `proot-distro kill ubuntu`（会结束容器内所有进程，慎用） |
| 主机 ↔ 容器复制 | `proot-distro copy 源 目标`，如 `proot-distro copy ~/a.txt ubuntu:/root/a.txt` |
| 目录同步 | `proot-distro sync 源 目标` |
| 备份容器 | `proot-distro backup ubuntu --output ~/ubuntu-backup.tar.xz` |
| 从备份恢复 | `proot-distro restore ~/ubuntu-backup.tar.xz`（**破坏性：会覆盖容器**） |

**必须保留的登录参数：**

| 参数 | 作用 |
|---|---|
| `--shared-tmp` | 容器 `/tmp` 与 Termux `$TMPDIR` 指向同一处，VirGL socket 才能互通 |
| `--no-sysvipc` | 规避该 PRoot 环境的 SysV IPC 兼容问题 |

> 不要执行 `proot-distro remove ubuntu` / `proot-distro reset ubuntu`，两者都会销毁数据。
> 恢复或改动容器身份文件前先备份，参见 [实机复现记录](10-实机复现记录.md) 中的 `aid_` 冲突处理。

## 4. 桌面与 GPU 服务

`y900` 已封装以下流程；需要手动排查时再单独运行：

| 用途 | 命令 |
|---|---|
| 启动 VirGL 服务 | `virgl_test_server_android --angle-vulkan --socket-path "$TMPDIR/y900-gpu-vtest"` |
| 启动 X11 | `termux-x11 :8 -tag gpu-test -extension MIT-SHM` |
| 打开 X11 窗口 | `am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity -d gpu-test` |
| 启动音频 | `pulseaudio --start --exit-idle-time=-1` |
| 开放容器访问音频 | `pactl load-module module-native-protocol-tcp listen=127.0.0.1 auth-ip-acl=127.0.0.1 port=4713` |
| 桌面引擎 | `start-tablet-gpu`（容器内 `/usr/local/bin/start-tablet-gpu`） |

两条链路互相独立：

```text
绘图：glmark2 / XFCE → virpipe → /tmp/y900-gpu-vtest → virgl_test_server_android → ANGLE Vulkan → Mali-G925
显示：DISPLAY=:8 → Termux:X11（窗口标签 gpu-test）→ Android 屏幕
```

`DISPLAY=:8` 能连上只说明显示通路正常，**不代表已经走 GPU**；验收必须看 renderer。

## 5. 验收与渲染器检查

| 用途 | 命令 | 通过标准 |
|---|---|---|
| 三场景基准 | `y900 test` | 输出含 `virgl (ANGLE (ARM, Vulkan ... Mali-G925 ...))`，正常退出 |
| 齿轮 + renderer | `y900 gears` | 窗口持续转动，`GL_RENDERER` 为 virgl/ANGLE |
| 容器内手动跑 | `y900 desk` 后执行 `glxgears -info` | 同上 |
| 显示服务器 | `xdpyinfo -display :8` | 能返回 X.Org 信息 |

> `glxinfo -B` 在该环境有已知 BadMatch 问题，不作为唯一验收依据。
> 短测分数接近软件渲染是正常现象，不能据此宣称“全面提速”；详见 [测试与验收](05-测试与验收.md)。

## 6. 分辨率、输入法与声音

| 用途 | 命令 |
|---|---|
| 改 X11 分辨率 | `y900 size 1600x1067` |
| 等价的偏好写法 | `termux-x11-preference displayResolutionMode:custom displayResolutionCustom:1600x1067` |
| 输入法 | 桌面已随 XFCE 自启 `fcitx5`，用其默认切换键切换 |
| 声音 | 容器内通过 `PULSE_SERVER=tcp:127.0.0.1:4713` 连 Termux 的 PulseAudio |

> 改分辨率只影响 Termux:X11 画布，不改变 Android 物理分辨率。

## 7. 日志与状态文件

| 路径 | 内容 |
|---|---|
| `~/.local/state/y900-xfce-gpu/session.json` | 当前桌面进程的 PID 与启动标识 |
| `~/.local/state/y900-xfce-gpu/desktop.log` | XFCE 启动日志 |
| `~/.local/state/y900-gpu/virgl.log` / `virgl.pid` | VirGL 服务日志与 PID |
| `~/.local/state/y900-gpu/x11.log` / `x11.pid` | Termux:X11 日志与 PID |
| `~/.local/share/y900-backup/` | 恢复基线前的备份（含容器身份文件备份） |
| `~/y900-termux-gpu-guide/` | 部署在 Termux HOME 的仓库副本 |

## 8. 常见故障对照

| 现象 | 检查 | 处理 |
|---|---|---|
| `Unrecognized option: -tag` | Termux:X11 版本过旧 | 升级到官方 nightly APK（1.03.01+） |
| `GPU 显示服务未就绪` | `y900 logs`；socket 是否存在 | 确认 `--shared-tmp`；必要时 `y900 stop` 后重试 |
| `useradd: UID ... is not unique` | 容器 `passwd` 中是否有 `aid_` 条目 | 备份后移除 `aid_` 行再重跑准备脚本，见 [实机复现记录](10-实机复现记录.md) |
| 重复 `y900 start` 多开窗口 | `y900 status` | 正常应幂等；异常时 `y900 stop` 再启动 |
| 跨屏投放后 X11 断开 | 桌面进程是否仍在 | 重新 `y900 open` 即可，桌面通常未退出 |
| glxgears 卡住 | 找到容器内 PID | 先 `kill <PID>`，不要直接杀整个桌面 |

## 9. 安全边界（沿用仓库约定）

- 不 `remove` / `reset` 已有容器；不改动 Android 原厂 GPU 驱动与 Vulkan ICD。
- 不切换到 GNOME、不 Root、不刷机；AVNC 支线未完成，不作为默认入口。
- 停止/重启前保存桌面工作；不盲目 `kill -9` 桌面或删除 socket 文件。
- 修改身份文件、系统配置前先做带时间戳的备份。
