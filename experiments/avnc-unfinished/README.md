# ⚠️ 未完成的 AVNC 实验（仅供研究，勿安装）

本目录保存的是 **2026-11-09 设备上实际安装的 `ubuntu-manager` 原文**。它包含一个**尚未验证成功**的 AVNC / x11vnc 共享分支。

## 不要这样做

```sh
# ❌ 不要执行：这会把未完成的 AVNC 管理器装成默认入口
install -m 755 experiments/avnc-unfinished/ubuntu-manager-avnc-unfinished "$PREFIX/bin/ubuntu-manager"
```

## 为什么

| 问题 | 说明 |
|---|---|
| 未验证 | RFB 握手未通过，AVNC 客户端认证与画面都没有成功记录 |
| 会阻断启动 | `start` / `x11` 冷启动可能先尝试起 VNC，失败即报错，容易被误判为 GPU 故障 |
| 额外攻击面 | 多一个 VNC 监听端口与密码文件 |
| 非 GPU 必需 | GPU 管线只需要 X11 显示，AVNC 只是远程查看的附加手段 |

## 应该用什么

日常使用与复现请用仓库根目录的 [`scripts/termux/ubuntu-manager`](../../scripts/termux/ubuntu-manager)（2026-10-20 已验证的纯 X11/GPU 基线）。

## 细节

完整的边界、已知错误与后续验证清单见
[`docs/07-AVNC实验边界.md`](../../docs/07-AVNC实验边界.md)。

## 文件

- `ubuntu-manager-avnc-unfinished` — 设备现装管理器原文，**原样保存，未修改**。注意其中会引用
  `/home/desktop/.vnc/passwd`、`~/.config/ubuntu-manager/initial-password`、
  `x11vnc`、`tigervncpasswd`，这些文件/程序都**不在**本仓库中。
