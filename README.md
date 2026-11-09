# Y900 Termux + Ubuntu ARM64 + XFCE + Termux:X11 + Mali GPU 复现指南

> 联想 Y900（TB711FU）平板上的 **Termux → PRoot Ubuntu ARM64 → XFCE → Termux:X11 → VirGL/ANGLE → Mali-G925** 图形链路归档与复现说明。
>
> 归档基准日：**2026-11-09**（Asia/Shanghai）。本仓库是原 ZIP 归档的整理版本，脚本与证据均来自实机只读采集；整理过程中只调整了目录结构与文档组织，没有修改设备。

**一句话结论：** 在「Termux:X11 的 `gpu-test` 窗口」里跑 `glmark2` / `glxgears`，可以拿到真实走 Mali-G925 的渲染器字符串（`virgl (ANGLE (ARM, Vulkan ... Mali-G925-Immortalis ...)`）。这条路径已验证。**但**这不等同于「整个桌面和所有应用都已硬件加速」，历史短测也没有证明整体提速；设备现装的 AVNC 分支尚未完成验证，不能作为默认入口。

---

## 1. 先看结论：哪些已验证，哪些没有

| 内容 | 状态 | 依据 |
|---|---|---|
| Ubuntu 24.04.5 ARM64 + XFCE 4.18 在 PRoot 容器内运行 | ✅ 已验证 | 实机运行、截图 `evidence/2026-10-20-XFCE.png` |
| Termux:X11 `:8`，窗口标签 `gpu-test` | ✅ 已验证 | 实机启动与截图 |
| Mesa `virpipe` → VirGL socket → `virgl_test_server_android --angle-vulkan` → ANGLE Vulkan → Android 原厂驱动 → Mali-G925 | ✅ 已验证 | `glxgears -info`、`glmark2` 的 renderer 输出 |
| `glmark2`（build / texture / shading 三场景）与 `glxgears` | ✅ 已验证 | `evidence/2026-10-17-CPU-GPU.txt`、`evidence/2026-10-20-CPU-GPU.txt`、`evidence/2026-10-20-unified-glxgears.txt` |
| 桌面脚本可重复启动、停止后能重建 socket | ✅ 已验证（2026-10-20 基线） | `scripts/termux/ubuntu-manager`、`scripts/ubuntu/start-tablet-gpu` |
| 独立的 Geeks3D **GpuTest** 程序 | ❌ 未安装、未验证 | `metadata/GpuTest-presence.txt` 仅有 `glmark2`、`glxgears`；PATH 及 `/opt`、`/usr/local` 未发现 |
| 通过 x11vnc 把 `:8` 桌面共享给 AVNC 客户端 | ⚠️ 未完成 | 归档记录：RFB 握手/认证未通过，无成功截图；见 [AVNC 实验边界](docs/07-AVNC实验边界.md) |
| 全桌面 / 所有应用硬件加速、帧率全面提升 | ❌ 未证明 | 短测分数与软件渲染接近，见 [历史验证记录](docs/08-历史验证记录.md) |
| GNOME 桌面 | ❌ 不属于本仓库目标 | 已从设备移除 |

> **`gpu-test` 是 Termux:X11 的窗口标签（`termux-x11 :8 -tag gpu-test`），不是独立软件包、可执行文件或 Vulkan 驱动名。**
> 本仓库所说的「GPU 测试」= 在该窗口运行 `glmark2` 和 `glxgears`。如果你需要真正的 Geeks3D GpuTest，请另行核对 ARM64 构建与来源，本仓库不声称已安装它。

---

## 2. 核心管线（不要改动这三处兼容参数）

```text
Ubuntu ARM64 OpenGL 程序（glmark2 / glxgears / XFCE）
  │  GALLIUM_DRIVER=virpipe
  │  VTEST_SOCKET_NAME=/tmp/y900-gpu-vtest
  ▼  Unix socket（靠 PRoot --shared-tmp 对齐）
Termux: virgl_test_server_android --angle-vulkan
  │  --socket-path "$TMPDIR/y900-gpu-vtest"
  ▼
ANGLE Vulkan 后端 → Android 原厂 Vulkan loader/驱动 → Mali-G925
```

显示方向则是独立的一条链路：

```text
Ubuntu X11 程序 → DISPLAY=:8 → Termux:X11（gpu-test 窗口）→ Android 显示
```

**VirGL socket 负责「OpenGL 绘图」，X11 socket 负责「显示与输入」，两者不可互相替代。**
`DISPLAY=:8` 本身不代表已经使用 GPU，验收必须检查实际测试程序输出的 renderer。

必须保留的本机兼容参数：

| 位置 | 参数 | 原因 |
|---|---|---|
| `proot-distro login` | `--shared-tmp` | 让容器内 `/tmp` 与 Termux `$TMPDIR` 指向同一处，VirGL socket 才能被两边看到 |
| `proot-distro login` | `--no-sysvipc` | 避免该 PRoot 环境下的 SysV IPC 兼容问题 |
| `termux-x11` | `-extension MIT-SHM` | 关闭 MIT-SHM 扩展，规避共享内存相关失败 |

不要照抄其他教程删掉这些参数。

---

## 3. 快速开始（Ubuntu 容器仍然存在时）

前提：平板已装好 Play 版 Termux、Termux:X11 APK、`proot-distro` 的 `ubuntu` 容器与 `desktop` 用户。**若容器已存在，绝对不要 `remove` / `reset` / 重装。**

### 3.1 把仓库放进 Termux HOME 并校验

把本仓库复制到 Termux 的 `$HOME`（例如 `~/y900-termux-gpu-guide`），然后在**普通 Termux**（不是容器内）执行：

```sh
cd "$HOME/y900-termux-gpu-guide"
sha256sum -c SHA256SUMS
```

> 从 Android 下载目录复制时不要转换换行符，脚本必须是 LF。Windows 上不要用会改 CRLF 的编辑器。

### 3.2 只读核对现状

```sh
proot-distro list
command -v ubuntu-manager
ubuntu-manager status
command -v termux-x11 virgl_test_server_android
```

### 3.3 恢复已验证的 X11/GPU 基线（会先备份被覆盖文件）

先保存工作并正常退出 XFCE。恢复脚本检测到 `xfce4-session` 在运行会拒绝继续：

```sh
bash scripts/restore-x11-baseline.sh
```

被覆盖的文件会备份到 `~/.local/share/y900-backup/archive-restore-<时间>-<PID>/`。脚本只替换归档列出的脚本与三个 XFCE XML 配置，不碰 rootfs 其余数据。

### 3.4 启动桌面并做冒烟测试

```sh
ubuntu-manager start
ubuntu-manager status
bash scripts/run-gpu-test.sh smoke
```

再打开 Android 上的 **Termux:X11** 应用，进入 `gpu-test` 窗口。系统可能阻止应用后台自动拉起窗口，手动切换即可；**不要因为没自动跳转就重复创建新桌面**。

### 3.5 验收标准（缺一不可）

- `glmark2` 的 build / texture / shading 三个场景正常结束，退出码 0；
- 图形窗口内容真实可见并持续更新；
- renderer 字符串同时包含 `virgl`、`ANGLE`、`Mali`，**而不是** `llvmpipe` / `softpipe`；
- 反复执行启动器不会多开 XFCE；停止后下次冷启动能重新建立 socket。

预期输出形如：

```text
GL_RENDERER = virgl (ANGLE (ARM, Vulkan 1.3.278 (Mali-G925-Immortalis MC1...)
GL_VERSION  = 2.1 Mesa 25.2.8-0ubuntu0.24.04.4
```

字符串末尾截断是历史输出原样，不代表错误，也不能当作完整 GPU 型号。

---

## 4. 仓库结构

```text
.
├── README.md                     # 本页：结论、管线、快速开始
├── docs/
│   ├── 01-环境与版本.md          # 设备、路径、依赖版本、软件源
│   ├── 02-架构与脚本.md          # 目录约定、脚本对照表、配置说明
│   ├── 03-恢复基线.md            # 已有容器恢复 + 空环境重建
│   ├── 04-手动启动.md            # 不依赖管理器的命令行启动与排错
│   ├── 05-测试与验收.md          # glmark2 / glxgears、compare、判读方法
│   ├── 06-常见问题.md            # 症状 → 检查点
│   ├── 07-AVNC实验边界.md        # 未完成实验的精确边界
│   ├── 08-历史验证记录.md        # 2026-10-17 / 10-20 的证据与分数
│   ├── 09-交接给新会话.md        # 可直接粘贴给新 AI 会话的说明
│   └── history/                  # 归档时的历史材料（只作参考）
├── scripts/
│   ├── termux/                   # 装到 Termux $PREFIX/bin 的管理器与转发入口
│   ├── ubuntu/                   # 装到容器 /usr/local/bin 的桌面启动脚本
│   ├── prepare-ubuntu.sh         # 可选：新镜像依赖准备（容器内管理员执行）
│   ├── restore-x11-baseline.sh   # 普通 Termux：带备份地安装基线
│   └── run-gpu-test.sh           # 普通 Termux：smoke / gears / compare
├── config/xfconf/                # 选定的 XFCE 配置（xfwm4 / xfce4-session / xsettings）
├── evidence/                     # 2026-10-17、10-20 的原始测试输出与截图
├── metadata/                     # 实机版本、软件源、设备属性、原始归档清单
├── experiments/avnc-unfinished/  # ⚠️ 未完成的 AVNC 管理器原文，仅供研究
├── tools/verify-repo.sh          # 本地校验：SHA256 + 脚本/XML 语法 + 链接
└── SHA256SUMS                    # 本仓库发布内容的校验清单
```

### 脚本一览

| 脚本 | 运行位置 | 作用 | 本轮是否在设备执行 |
|---|---|---|---|
| `scripts/termux/ubuntu-manager` | 普通 Termux | **唯一基线管理器**：启动显示、VirGL、音频与 XFCE | 2026-10-20 已验证，本轮只读采集 |
| `scripts/termux/ubuntu-gpu` | 普通 Termux | 兼容转发到管理器；`shell` 转 `gpu-shell` | 转发脚本，静态检查 |
| `scripts/termux/ubuntu-xfce-gpu` | 普通 Termux | 同上，不另外创建桌面 | 转发脚本，静态检查 |
| `scripts/termux/ubuntu-desktop` | 普通 Termux | 等价于 `ubuntu-manager start` | 转发脚本，静态检查 |
| `scripts/termux/ubuntu-stop` | 普通 Termux | 等价于 `ubuntu-manager stop` | 转发脚本，静态检查 |
| `scripts/ubuntu/start-tablet-gpu` | 容器内 desktop | 导出图形/GPU/输入法环境，独立 D-Bus 后启动 XFCE | 2026-10-20 已验证 |
| `scripts/ubuntu/y900-live-session` | 容器内 | 给经 SSH 启动的程序导入 `:8` 的实际会话环境 | 2026-10-20 已验证 |
| `scripts/restore-x11-baseline.sh` | 普通 Termux | 检查依赖、备份旧文件、安装基线；**不启动桌面** | ❌ 仅静态检查 |
| `scripts/prepare-ubuntu.sh` | 容器内管理员 | 可选的新镜像依赖准备；不改已有用户 UID | ❌ 仅静态检查 |
| `scripts/run-gpu-test.sh` | 普通 Termux | `smoke` / `gears` / `compare` 三个测试入口 | ❌ 仅静态检查 |

> 「仅静态检查」= 通过了 `bash -n` / `python -m py_compile` / XML 解析，但没有在设备上实际运行过。首次使用请按文档逐步执行并观察输出。

---

## 5. 版本基线（实机读取，2026-11-09）

| 组件 | 版本 |
|---|---|
| Termux | Google Play 分支，包名 `com.termux` |
| `proot` | 5.1.107.80 |
| `proot-distro` | 5.3.0 |
| `termux-x11-nightly` | 1.03.01-5 |
| `virglrenderer-android` | 1.3.0 |
| `angle-android` | 2.1.24923-f09a19ce-2 |
| `vulkan-loader-android` | 29 |
| `pulseaudio` | 17.0-3 |
| Ubuntu | 24.04.5 LTS / aarch64 |
| `xfce4-session` | 4.18.3-1build2 |
| `xfwm4` | 4.18.0-1build3 |
| `glmark2-x11` | 2023.01+dfsg-1build2 |
| `mesa-utils` | 9.0.0-2 |
| `libgl1-mesa-dri:arm64` | 25.2.8-0ubuntu0.24.04.4 |

完整清单见 [`metadata/Termux-packages.txt`](metadata/Termux-packages.txt)、[`metadata/Ubuntu-packages.txt`](metadata/Ubuntu-packages.txt) 与 [`metadata/package-origins.txt`](metadata/package-origins.txt)。

> 不要为了「匹配版本」盲目切换 Termux 分支、软件源或 Vulkan ICD。先比较版本、包架构和命令帮助。

---

## 6. 必须知道的边界

- **AVNC 实验不是默认安装入口。** 设备当时安装的 `ubuntu-manager` 含未完成的 AVNC 分支，原文保存在 `experiments/avnc-unfinished/`，脚本里可能引用 `.vnc/passwd`、`x11vnc` 和 `tigervncpasswd`。本仓库的 `scripts/` 是纯 X11/GPU 基线，恢复脚本不会安装或启动 AVNC。
- **不要声称全面加速。** 历史短测（软件 141 vs GPU 140；另一次 96 vs 94）没有证明整体提速，且受后台图形负载影响。详见 [历史验证记录](docs/08-历史验证记录.md)。
- **不要把 glxinfo 当唯一验收。** 该 Virpipe 路径上 `glxinfo -B` 有已知 `X_GetImage BadMatch` 兼容问题，用 `glmark2` / `glxgears` 的实际绘图来判断。
- **本仓库不含**：APK、完整 rootfs、软件包二进制、SSH 私钥、VNC 密码、API Key、浏览器资料、个人项目、输入法词库。它恢复的是**脚本与运行路径**，不能离线重建完全相同的二进制环境。

---

## 7. 文档索引

| 想做什么 | 看这里 |
|---|---|
| 了解设备、路径、版本、软件源 | [01-环境与版本](docs/01-环境与版本.md) |
| 搞清每个脚本装到哪里、配置在哪 | [02-架构与脚本](docs/02-架构与脚本.md) |
| 在现有容器上恢复并启动 | [03-恢复基线](docs/03-恢复基线.md) |
| 从空环境重建（高风险，可选） | [03-恢复基线 §4](docs/03-恢复基线.md#4-从空环境重建可选高风险) |
| 不用管理器、纯命令行拉起管线 | [04-手动启动](docs/04-手动启动.md) |
| 跑测试、判断是否真的走了 GPU | [05-测试与验收](docs/05-测试与验收.md) |
| 报错排查 | [06-常见问题](docs/06-常见问题.md) |
| AVNC 到底做到哪一步 | [07-AVNC实验边界](docs/07-AVNC实验边界.md) |
| 历史测试数据与结论边界 | [08-历史验证记录](docs/08-历史验证记录.md) |
| 把任务交给新的 AI 会话 | [09-交接给新会话](docs/09-交接给新会话.md) |

---

## 8. 校验与来源

```sh
sha256sum -c SHA256SUMS          # 校验本仓库全部发布文件
bash tools/verify-repo.sh        # 额外检查脚本语法、XML 与文档相对链接
```

原始归档：`Y900-Termux-GPU归档-2026-11-09.zip`
SHA-256：`c6d481e2ded2eb97b37f387c0455a3f7ec7a025bb26a8b7be74e525f4a5b2688`

本仓库在原归档基础上做了目录整理：`observed-device/` 下的 AVNC 管理器移入 `experiments/avnc-unfinished/`，历史指令表移入 `docs/history/`，新增本 README 与分主题文档，并**重新生成**了 `SHA256SUMS`。原始归档的逐文件清单保留在 [`metadata/manifest-original-archive.json`](metadata/manifest-original-archive.json)（其中路径对应整理前的布局）。

---

## 9. 参考

- [Termux:X11](https://github.com/termux/termux-x11)
- [Play 分支 Termux 软件包](https://github.com/termux-play-store/termux-packages)
- [PRoot Distro](https://github.com/termux/proot-distro)
- [ANGLE](https://chromium.googlesource.com/angle/angle)
- [VirGL](https://virgil3d.github.io/)

实际复现请优先以本机包版本、命令帮助与本仓库脚本为准；上游文档与仓库会随时间变化。
