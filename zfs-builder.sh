#!/usr/bin/env bash
# ============================================================================
# ZFS 预编译模块打包工具
# 在 Debian 编译机上运行，可为多个内核版本编译 ZFS 模块并打包
#
# 用法:
#   交互式菜单: sudo bash zfs-builder.sh
#   命令行模式: sudo bash zfs-builder.sh --all
#
# 产出: ./output/zfs-modules-<内核版本>.tar.gz
# ============================================================================
set -euo pipefail

# ========================== 颜色定义 ==========================
readonly RED='\033[1;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly CYAN='\033[1;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ========================== 全局变量 ==========================
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
OUTPUT_DIR="$(pwd)/output"
KERNEL_LIST=()         # 可用内核版本缓存
TARGET_KERNELS=()      # 选中要编译的内核版本
CLI_MODE=""            # 命令行模式（空 = 交互式）

# ========================== 工具函数 ==========================
log()   { echo -e "${GREEN}[✓]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}[▶]${NC} ${BOLD}$1${NC}"; }

divider() {
    echo -e "${DIM}────────────────────────────────────────────────────${NC}"
}

# ========================== 显示横幅 ==========================
show_banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║                                                  ║${NC}"
    echo -e "${CYAN}  ║        ${BOLD}ZFS 预编译模块打包工具${NC}${CYAN}                   ║${NC}"
    echo -e "${CYAN}  ║        ${DIM}Multi-Kernel ZFS Module Builder${NC}${CYAN}            ║${NC}"
    echo -e "${CYAN}  ║                                                  ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ========================== 环境检查 ==========================
check_environment() {
    if [[ "$EUID" -ne 0 ]]; then
        error "请以 root 权限运行此脚本"
        echo -e "  ${DIM}用法: sudo bash $0${NC}"
        exit 1
    fi

    if [[ ! -f /etc/os-release ]]; then
        error "无法检测操作系统"
        exit 1
    fi

    source /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
        error "此脚本仅支持 Debian 系统（当前: ${ID:-unknown}）"
        exit 1
    fi
}

# ========================== 显示系统信息 ==========================
show_system_info() {
    source /etc/os-release 2>/dev/null || true

    divider
    echo -e "  ${BOLD}编译机信息${NC}"
    divider
    echo -e "  操作系统  :  ${GREEN}Debian ${VERSION_ID:-?}${NC} (${VERSION_CODENAME:-?})"
    echo -e "  当前内核  :  ${GREEN}$(uname -r)${NC}"
    echo -e "  系统架构  :  ${GREEN}${ARCH}${NC}"
    echo -e "  输出目录  :  ${GREEN}${OUTPUT_DIR}${NC}"

    # 检查已生成的预编译包
    if [[ -d "$OUTPUT_DIR" ]]; then
        local pkg_count
        pkg_count=$(find "$OUTPUT_DIR" -name "zfs-modules-*.tar.gz" 2>/dev/null | wc -l)
        if [[ "$pkg_count" -gt 0 ]]; then
            echo -e "  已有产出  :  ${YELLOW}${pkg_count} 个预编译包${NC}"
        else
            echo -e "  已有产出  :  ${DIM}无${NC}"
        fi
    else
        echo -e "  已有产出  :  ${DIM}无${NC}"
    fi

    # 检查编译基础是否就绪
    if command -v dkms &>/dev/null && dpkg -l build-essential 2>/dev/null | grep -q '^ii'; then
        echo -e "  编译环境  :  ${GREEN}已就绪${NC}"
    else
        echo -e "  编译环境  :  ${DIM}未安装（首次编译时自动安装）${NC}"
    fi

    divider
    echo ""
}

# ========================== 获取可用内核列表 ==========================
refresh_kernel_list() {
    info "查询可用的内核版本..."
    apt-get update -qq 2>/dev/null

    KERNEL_LIST=()
    local headers
    headers=$(apt-cache search '^linux-headers-[0-9]' 2>/dev/null \
        | awk '{print $1}' \
        | sed 's/^linux-headers-//' \
        | sort -V)

    while IFS= read -r kver; do
        [[ -z "$kver" ]] && continue
        KERNEL_LIST+=("$kver")
    done <<< "$headers"

    log "找到 ${#KERNEL_LIST[@]} 个可用内核版本"
}

# ========================== 显示内核版本列表 ==========================
show_kernel_list() {
    if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
        refresh_kernel_list
    fi

    local current
    current=$(uname -r)

    echo ""
    divider
    echo -e "  ${BOLD}可用的内核版本（共 ${#KERNEL_LIST[@]} 个）${NC}"
    divider

    local i
    for i in "${!KERNEL_LIST[@]}"; do
        local kver="${KERNEL_LIST[$i]}"
        local num=$((i + 1))

        # 检查是否已有预编译包
        local has_pkg=""
        if [[ -f "${OUTPUT_DIR}/zfs-modules-${kver}.tar.gz" ]]; then
            has_pkg="  ${GREEN}[已编译]${NC}"
        fi

        # 标记当前内核
        if [[ "$kver" == "$current" ]]; then
            printf "    ${CYAN}%2d)${NC}  ${GREEN}%-40s${NC} ${YELLOW}← 当前内核${NC}%b\n" "$num" "$kver" "$has_pkg"
        else
            printf "    ${CYAN}%2d)${NC}  %-40s%b\n" "$num" "$kver" "$has_pkg"
        fi
    done

    divider
    echo ""
}

# ========================== 显示已编译的包 ==========================
show_packages() {
    echo ""
    divider
    echo -e "  ${BOLD}已生成的预编译包${NC}"
    divider

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        echo -e "  ${DIM}暂无产出文件${NC}"
        divider
        echo ""
        return
    fi

    local count=0
    for f in "${OUTPUT_DIR}"/zfs-modules-*.tar.gz; do
        [[ -f "$f" ]] || continue
        count=$((count + 1))

        local fname
        fname=$(basename "$f")
        local fsize
        fsize=$(du -h "$f" | awk '{print $1}')
        local fdate
        fdate=$(date -r "$f" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "?")
        local fmd5
        fmd5=$(md5sum "$f" 2>/dev/null | awk '{print $1}' || echo "?")

        # 提取内核版本
        local kver="${fname#zfs-modules-}"
        kver="${kver%.tar.gz}"

        echo -e "  ${GREEN}✓${NC}  ${BOLD}${fname}${NC}"
        echo -e "     内核: ${kver}  |  大小: ${fsize}  |  日期: ${fdate}"
        echo -e "     MD5:  ${DIM}${fmd5}${NC}"
        echo ""
    done

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${DIM}暂无产出文件${NC}"
    else
        echo -e "  共 ${GREEN}${count}${NC} 个预编译包"
    fi

    divider
    echo ""
}

# ========================== 主菜单 ==========================
show_menu() {
    echo -e "  ${BOLD}请选择操作：${NC}"
    echo ""
    echo -e "    ${CYAN}1)${NC}  编译当前内核版本  ${DIM}─  快速编译 $(uname -r)${NC}"
    echo -e "    ${CYAN}2)${NC}  选择内核版本编译  ${DIM}─  从列表中选择${NC}"
    echo -e "    ${CYAN}3)${NC}  编译所有可用版本  ${DIM}─  批量全部编译${NC}"
    echo ""
    echo -e "    ${CYAN}4)${NC}  查看可用内核版本"
    echo -e "    ${CYAN}5)${NC}  查看已编译的包"
    echo -e "    ${CYAN}6)${NC}  查看编译机信息"
    echo -e "    ${CYAN}0)${NC}  退出"
    echo ""
    echo -ne "  ${BOLD}请输入选项 [0-6]: ${NC}"
}

# ========================== 选择内核版本 ==========================
select_kernels() {
    if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
        refresh_kernel_list
    fi

    if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
        error "未找到任何可用的内核版本"
        return 1
    fi

    show_kernel_list

    echo -e "  ${DIM}输入编号选择要编译的版本，多个用空格分隔${NC}"
    echo -e "  ${DIM}输入 A 编译全部，输入 0 返回菜单${NC}"
    echo ""
    echo -ne "  ${BOLD}请选择: ${NC}"
    read -r selection

    if [[ "$selection" == "0" ]]; then
        return 1
    fi

    TARGET_KERNELS=()

    if [[ "$selection" =~ ^[aA]$ ]]; then
        TARGET_KERNELS=("${KERNEL_LIST[@]}")
        return 0
    fi

    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#KERNEL_LIST[@]}" ]]; then
            TARGET_KERNELS+=("${KERNEL_LIST[$((num - 1))]}")
        else
            warn "忽略无效编号: ${num}"
        fi
    done

    if [[ ${#TARGET_KERNELS[@]} -eq 0 ]]; then
        warn "未选择任何内核版本"
        return 1
    fi

    return 0
}

# ========================== 安装编译基础 ==========================
install_build_base() {
    step "安装编译基础环境..."

    export DEBIAN_FRONTEND=noninteractive

    # 确保 contrib 源已启用
    local contrib_enabled=false
    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        grep -q "contrib" /etc/apt/sources.list.d/debian.sources 2>/dev/null && contrib_enabled=true
    fi
    if [[ -f /etc/apt/sources.list ]]; then
        grep -q "contrib" /etc/apt/sources.list 2>/dev/null && contrib_enabled=true
    fi

    if [[ "$contrib_enabled" == "false" ]]; then
        info "启用 contrib 组件..."
        if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
            sed -i 's/Components: main$/Components: main contrib/' \
                /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
        elif [[ -f /etc/apt/sources.list ]]; then
            sed -i '/^deb.*main/ { /contrib/! s/main/main contrib/ }' \
                /etc/apt/sources.list 2>/dev/null || true
        fi
        apt-get update -qq 2>/dev/null
    fi

    # 安装编译工具链
    apt-get install -y -qq build-essential dkms >/dev/null 2>&1
    log "编译工具链就绪"

    # 安装 ZFS DKMS 源码
    info "安装 ZFS DKMS 源码包..."
    apt-get install -y -qq zfs-dkms >/dev/null 2>&1 || {
        apt-get install -y -qq zfsutils-linux >/dev/null 2>&1 || true
    }

    local zfs_ver
    zfs_ver=$(dkms status 2>/dev/null | grep -oP 'zfs[/,]\s*\K[0-9.]+' | head -n1 || echo "?")
    log "ZFS DKMS 源码版本: ${zfs_ver}"
}

# ========================== 为单个内核编译 ==========================
build_for_kernel() {
    local kernel_ver="$1"
    local index="$2"
    local total="$3"

    echo ""
    divider
    echo -e "  ${BOLD}编译 [${index}/${total}]${NC}  内核: ${GREEN}${kernel_ver}${NC}"
    divider

    # 检查是否已有包
    if [[ -f "${OUTPUT_DIR}/zfs-modules-${kernel_ver}.tar.gz" ]]; then
        info "已存在预编译包，跳过（如需重新编译请先删除旧包）"
        return 0
    fi

    # 安装对应的内核头文件
    info "安装 linux-headers-${kernel_ver}..."
    if ! apt-get install -y -qq "linux-headers-${kernel_ver}" >/dev/null 2>&1; then
        error "linux-headers-${kernel_ver} 安装失败"
        return 1
    fi

    # 获取 ZFS DKMS 版本号
    local zfs_ver
    zfs_ver=$(dkms status 2>/dev/null | grep -oP 'zfs[/,]\s*\K[0-9.]+' | head -n1)
    if [[ -z "$zfs_ver" ]]; then
        error "无法获取 ZFS DKMS 版本号"
        return 1
    fi

    # DKMS 编译
    info "DKMS 编译 ZFS ${zfs_ver} → ${kernel_ver}..."
    local start_time=$SECONDS

    dkms remove "zfs/${zfs_ver}" -k "$kernel_ver" 2>/dev/null || true
    if ! dkms build "zfs/${zfs_ver}" -k "$kernel_ver" 2>/dev/null; then
        error "DKMS build 失败"
        return 1
    fi
    if ! dkms install "zfs/${zfs_ver}" -k "$kernel_ver" 2>/dev/null; then
        error "DKMS install 失败"
        return 1
    fi

    local elapsed=$(( SECONDS - start_time ))
    info "编译耗时: ${elapsed} 秒"

    # 查找模块文件
    local found_dir=""
    local search_dirs=(
        "/lib/modules/${kernel_ver}/updates/dkms"
        "/lib/modules/${kernel_ver}/extra"
    )
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]] && find "$dir" -name "zfs.ko*" 2>/dev/null | grep -q .; then
            found_dir="$dir"
            break
        fi
    done
    if [[ -z "$found_dir" ]]; then
        found_dir=$(find "/lib/modules/${kernel_ver}" -name "zfs.ko*" -printf '%h\n' 2>/dev/null | head -n1 || true)
    fi
    if [[ -z "$found_dir" ]]; then
        error "编译后未找到模块文件"
        return 1
    fi

    # 打包
    local package_name="zfs-modules-${kernel_ver}"
    local pack_tmp="/tmp/zfs-pack-$$"
    local pack_dir="${pack_tmp}/${package_name}"
    rm -rf "$pack_tmp" 2>/dev/null || true
    mkdir -p "${pack_dir}/modules"

    find "$found_dir" -name "*.ko*" -type f -exec cp {} "${pack_dir}/modules/" \;

    local ko_count
    ko_count=$(find "${pack_dir}/modules" -name "*.ko*" -type f | wc -l)
    local rel_path="${found_dir#/lib/modules/${kernel_ver}/}"

    local zfs_modver
    zfs_modver=$(modinfo "${pack_dir}/modules/"zfs.ko* 2>/dev/null | awk '/^version:/ {print $2}' | head -n1 || echo "$zfs_ver")

    # 元数据
    cat > "${pack_dir}/metadata.txt" <<META
# ZFS 预编译模块元数据
kernel_version=${kernel_ver}
architecture=${ARCH}
debian_version=$(cat /etc/debian_version 2>/dev/null || echo "unknown")
debian_codename=${VERSION_CODENAME:-unknown}
module_path=${rel_path}
zfs_version=${zfs_modver}
build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
module_count=${ko_count}
META

    mkdir -p "$OUTPUT_DIR"
    tar -czf "${OUTPUT_DIR}/${package_name}.tar.gz" -C "$pack_tmp" "${package_name}/"

    local file_size
    file_size=$(du -h "${OUTPUT_DIR}/${package_name}.tar.gz" | awk '{print $1}')

    rm -rf "$pack_tmp" 2>/dev/null || true

    log "完成: ${package_name}.tar.gz (${file_size}, ${ko_count} 个模块)"
    return 0
}

# ========================== 执行编译 ==========================
do_build() {
    local total=${#TARGET_KERNELS[@]}

    # 显示编译计划
    echo ""
    divider
    echo -e "  ${BOLD}编译计划（共 ${total} 个内核版本）${NC}"
    divider
    for kver in "${TARGET_KERNELS[@]}"; do
        if [[ -f "${OUTPUT_DIR}/zfs-modules-${kver}.tar.gz" ]]; then
            echo -e "    ${YELLOW}•${NC}  ${kver}  ${DIM}(已有包，将跳过)${NC}"
        else
            echo -e "    ${CYAN}•${NC}  ${kver}"
        fi
    done
    divider
    echo ""
    echo -ne "  ${BOLD}确认开始编译？${NC}[y/N]: "
    read -r confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { info "已取消"; return; }

    # 安装编译基础
    install_build_base

    # 逐个编译
    local success=0
    local skipped=0
    local failed=0
    local i=0

    for kernel_ver in "${TARGET_KERNELS[@]}"; do
        i=$((i + 1))
        if build_for_kernel "$kernel_ver" "$i" "$total"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
            warn "跳过失败的版本，继续..."
        fi
    done

    # 结果
    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║                                                  ║${NC}"
    echo -e "${GREEN}  ║          ✓  编译完成                             ║${NC}"
    echo -e "${GREEN}  ║                                                  ║${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  成功: ${GREEN}${success}${NC}  |  失败: ${RED}${failed}${NC}  |  总计: ${total}"
    echo ""

    show_packages

    divider
    echo -e "  ${BOLD}后续操作：${NC}"
    echo ""
    echo -e "  1. 将 ${CYAN}output/${NC} 目录中的文件拉回本地"
    echo -e "  2. 在 GitHub 仓库创建 Release（Tag: ${CYAN}zfs-prebuilt${NC}）"
    echo -e "  3. 将所有 .tar.gz 文件上传为 Release Assets"
    echo -e "  4. 更新 Incudal.sh 中的 ${CYAN}ZFS_PREBUILT_URL${NC} 地址"
    divider
    echo ""
}

# ========================== CLI 参数解析 ==========================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                CLI_MODE="all"; shift ;;
            --list|-l)
                CLI_MODE="list"; shift ;;
            --kernel|-k)
                CLI_MODE="specific"
                TARGET_KERNELS+=("$2"); shift 2 ;;
            --help|-h)
                echo "用法: sudo bash $0 [选项]"
                echo ""
                echo "选项:"
                echo "  (无参数)              进入交互式菜单"
                echo "  --all, -a             编译所有可用内核版本"
                echo "  --kernel, -k <VER>    编译指定内核版本（可多次使用）"
                echo "  --list, -l            列出可用内核版本"
                echo "  --help, -h            显示帮助"
                exit 0 ;;
            *)
                error "未知参数: $1"; exit 1 ;;
        esac
    done
}

# ========================== 主流程 ==========================
main() {
    parse_args "$@"
    show_banner
    check_environment

    # CLI 快捷模式
    case "$CLI_MODE" in
        list)
            refresh_kernel_list
            show_kernel_list
            exit 0
            ;;
        all)
            refresh_kernel_list
            TARGET_KERNELS=("${KERNEL_LIST[@]}")
            do_build
            exit 0
            ;;
        specific)
            do_build
            exit 0
            ;;
    esac

    # ---- 交互式菜单循环 ----
    show_system_info

    while true; do
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1)
                # 编译当前内核
                TARGET_KERNELS=("$(uname -r)")
                do_build
                ;;
            2)
                # 选择内核版本
                if select_kernels; then
                    do_build
                fi
                ;;
            3)
                # 编译全部
                if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
                    refresh_kernel_list
                fi
                if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
                    error "未找到可用的内核版本"
                    continue
                fi
                TARGET_KERNELS=("${KERNEL_LIST[@]}")
                do_build
                ;;
            4)
                # 查看可用内核
                if [[ ${#KERNEL_LIST[@]} -eq 0 ]]; then
                    refresh_kernel_list
                fi
                show_kernel_list
                ;;
            5)
                # 查看已编译的包
                show_packages
                ;;
            6)
                # 查看系统信息
                show_system_info
                ;;
            0)
                info "再见！"
                exit 0
                ;;
            *)
                warn "无效选项，请重新选择"
                ;;
        esac
    done
}

main "$@"
