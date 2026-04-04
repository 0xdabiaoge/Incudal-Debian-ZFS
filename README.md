# Incudal Node Setup (Incudal 节点安装管理脚本)

Incudal 节点管理脚本旨在为 [Incudal 面板](https://incudal.com) 打造一款现代化、一键式、高容错的 LXC 容器宿主机部署与维护工具。该脚本完美集成了 Incus 环境配置、Debian 专属的 ZFS 预编译分发以及 RFW 流量拦截防火墙，让你在极短时间内完成业务结点的搭建与销毁。

## ✨ 核心特性

- **🚀 全自动 Incus 部署**：一键完成系统依赖注入、内核参数调整以及网桥管理（支持纯 IPv4 或 NAT+IPv6 模式）。
- **📦 智能 Debian ZFS 处理**：
  - 首选从 GitHub Release ([Incudal-Debian-ZFS](https://github.com/0xdabiaoge/Incudal-Debian-ZFS)) 自动匹配内核拉取预编译模块，实现“秒级挂载”。
  - 智能回退机制：若无适配的预编译包，可提供即时 DKMS 编译选项。编译完成后自动清理 `build-essential` 等工具链。
- **🛡️ RFW 入站屏蔽防火墙集成**：
  - 基于 Rust && eBPF 的高性能防护。
  - **动态交互配置**：脚本内建界面供您灵活选择屏蔽协议（SMTP, HTTP, SOCKS5, FET[全加密], WireGuard, QUIC）配置。
  - **GeoIP 黑/白名单**：一键锁定国家级来源流量拦截，并支持开启后台 eBPF 拦截日志状态跟踪。
- **🧹 自杀式彻底卸载还原**：
  - 无论系统包损坏或发生了什么样的残留，执行彻底卸载命令能够瞬间强制清理所有的 Incus 后台、存储池、网桥与软件包。
  - **卸载后自行销毁**：配置清理完毕后，安装脚本会将自身等所有残余文件从磁盘上完全根除。

---

## 🛠️ 环境要求

- **操作系统**: Debian 12 (bookworm) 纯净环境（推荐）
- **架构**: x86_64 或 aarch64
- **权限**: 必须以 `root` 用户运行

## 🖥️ 交互式 TUI 菜单

```
(curl -LfsS https://raw.githubusercontent.com/0xdabiaoge/Incudal-Debian-ZFS/blob/main/Incudal.sh -o /usr/local/bin/incudal || wget -q https://raw.githubusercontent.com/0xdabiaoge/Incudal-Debian-ZFS/blob/main/Incudal.sh -O /usr/local/bin/incudal) && chmod +x /usr/local/bin/incudal && incudal
```

**快捷命令：incudal**

**主菜单功能项：**
1. **安装节点 (NAT 模式)**：使用 IPv4 NAT 环境部署 Incus 和 ZFS。
2. **安装节点 (NAT + IPv6 模式)**：部署同时支持 IPv6 栈的 Incus。
3. **安装 RFW 入站流量屏蔽防火墙**：动态定制安装高性能流量防火墙。
4. **查看系统信息**：输出主机的系统概况及目前的 Incus 版本运行架构和 RFW 的运行拦截规则状态。
5. **卸载 RFW**：平滑移除防火墙。
6. **卸载节点**：**【终极杀手剑】** 用于删除清理所有的 LXC 容器、镜像、Incus 设定、ZFS 池、移除相关包以及本安装脚本自身的系统原初状态恢复。
0. **退出**

---

## 📖 组成与项目结构

该系统主要包含以下组件文件（如果您需要自行开发维护）：

- `Incudal.sh`：面向用户的宿主机终端交互系统与安装/卸载逻辑主体。
- `zfs-builder.sh`：面向编译机的 ZFS Debian 独立批量并行编译系统。每次 Debian 升级官方内核后，在此机器上运行构建，成品将自动推送至 `0xdabiaoge/Incudal-Debian-ZFS` 仓库供 `Incudal.sh` 极速拉取。

---

## ⚠️ 注意事项

- **内核更新锁定**：由于 ZFS OOT 原理所限，`Incudal.sh` 在配设成功后会默认利用 `apt-mark hold` 锁死您的内核以防止后台随意升级引发 ZFS 断层挂掉。
- **关于 RFW 测试**：启用 RFW 拦截（如阻挡所有中国大陆特征的 HTTP / SOCKS5）前，请确保您当前登入 SSH 的链路**不受该限制影响**（通常 SSH / 22 默认均被直接放行）。

---
**Powered by Antigravity / Google DeepMind & Incudal Team**
