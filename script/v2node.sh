#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 实例名为空时对应默认实例（/etc/v2node/config.json, v2node.service），
# 保证不带实例名的既有用法完全不受影响
instance_service_name() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "v2node@$1"
    fi
}

instance_config_path() {
    if [[ -z "$1" ]]; then
        echo "/etc/v2node/config.json"
    else
        echo "/etc/v2node/instances/$1/config.json"
    fi
}

# 命名实例各自一个文件夹（/etc/v2node/instances/<name>/）；默认实例沿用原本
# 的 /etc/v2node/config.json，不进文件夹
instance_dir() {
    if [[ -z "$1" ]]; then
        echo "/etc/v2node"
    else
        echo "/etc/v2node/instances/$1"
    fi
}

instance_init_name() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "v2node.$1"
    fi
}

# 统一给日志/提示用的名字：默认实例就叫"v2node"，命名实例叫"实例 [name]"
instance_label() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "实例 [$1]"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启v2node" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start "" 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 v2node，请使用 v2node log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# $1: 实例名(空=默认实例) $2: silent(非空=不返回主菜单，供CLI用)
config() {
    local name="$1"
    local silent="$2"
    local cfg=$(instance_config_path "$name")
    if [[ ! -f "$cfg" ]]; then
        echo -e "${red}$(instance_label "$name") 还没有配置文件${plain}"
        [[ -n "$name" ]] && echo -e "${yellow}请先执行: v2node new ${name}${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    echo "修改配置后会自动尝试重启$(instance_label "$name")"
    vi "$cfg"
    sleep 2
    restart "$name" 0
    check_status "$name"
    case $? in
        0)
            echo -e "$(instance_label "$name")状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到$(instance_label "$name")未启动或自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               log "$name" "" 0
            fi
            ;;
        2)
            echo -e "$(instance_label "$name")状态: ${red}未安装${plain}"
    esac
    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

# 完全卸载：连同所有命名实例一起停用/移除，不留下孤儿 service
uninstall() {
    confirm "确定要卸载 v2node 吗（会连同所有实例一起移除）?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    local d name
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            name=$(basename "$d")
            if [[ x"${release}" == x"alpine" ]]; then
                service $(instance_init_name "$name") stop 2>/dev/null
                rc-update del $(instance_init_name "$name") 2>/dev/null
            else
                systemctl stop "$(instance_service_name "$name")" 2>/dev/null
                systemctl disable "$(instance_service_name "$name")" 2>/dev/null
            fi
        done
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node stop
        rc-update del v2node
        rm /etc/init.d/v2node -f
        rm /etc/init.d/v2node.* -f 2>/dev/null
    else
        systemctl stop v2node
        systemctl disable v2node
        rm /etc/systemd/system/v2node.service -f
        rm /etc/systemd/system/v2node@.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/v2node/ -rf
    rm /usr/local/v2node/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/v2node -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 以下生命周期指令统一格式: FUNC [实例名] [silent]
# 实例名留空 = 默认实例(v2node.service / /etc/v2node/config.json)
# silent 非空时不会在结尾进交互菜单，供 CLI 直接调用；菜单调用时留空即可

start() {
    local name="$1"
    local silent="$2"
    check_status "$name"
    local st=$?
    if [[ $st == 2 ]]; then
        echo -e "${red}$(instance_label "$name") 还没有安装或配置${plain}"
    elif [[ $st == 0 ]]; then
        echo ""
        echo -e "${green}$(instance_label "$name") 已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$name") start
        else
            systemctl start "$(instance_service_name "$name")"
        fi
        sleep 2
        check_status "$name"
        if [[ $? == 0 ]]; then
            echo -e "${green}$(instance_label "$name") 启动成功，请使用 v2node log${name:+ $name} 查看运行日志${plain}"
        else
            echo -e "${red}$(instance_label "$name") 可能启动失败，请稍后使用 v2node log${name:+ $name} 查看日志信息${plain}"
        fi
    fi

    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

stop() {
    local name="$1"
    local silent="$2"
    if [[ x"${release}" == x"alpine" ]]; then
        service $(instance_init_name "$name") stop
    else
        systemctl stop "$(instance_service_name "$name")"
    fi
    sleep 2
    check_status "$name"
    if [[ $? == 1 ]]; then
        echo -e "${green}$(instance_label "$name") 停止成功${plain}"
    else
        echo -e "${red}$(instance_label "$name") 停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

restart() {
    local name="$1"
    local silent="$2"
    if [[ x"${release}" == x"alpine" ]]; then
        service $(instance_init_name "$name") restart
    else
        systemctl restart "$(instance_service_name "$name")"
    fi
    sleep 2
    check_status "$name"
    if [[ $? == 0 ]]; then
        echo -e "${green}$(instance_label "$name") 重启成功，请使用 v2node log${name:+ $name} 查看运行日志${plain}"
    else
        echo -e "${red}$(instance_label "$name") 可能启动失败，请稍后使用 v2node log${name:+ $name} 查看日志信息${plain}"
    fi
    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

status() {
    local name="$1"
    local silent="$2"
    if [[ x"${release}" == x"alpine" ]]; then
        service $(instance_init_name "$name") status
    else
        systemctl status "$(instance_service_name "$name")" --no-pager -l
    fi
    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

enable() {
    local name="$1"
    local silent="$2"
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add $(instance_init_name "$name")
    else
        systemctl enable "$(instance_service_name "$name")"
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}$(instance_label "$name") 设置开机自启成功${plain}"
    else
        echo -e "${red}$(instance_label "$name") 设置开机自启失败${plain}"
    fi

    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

disable() {
    local name="$1"
    local silent="$2"
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del $(instance_init_name "$name")
    else
        systemctl disable "$(instance_service_name "$name")"
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}$(instance_label "$name") 取消开机自启成功${plain}"
    else
        echo -e "${red}$(instance_label "$name") 取消开机自启失败${plain}"
    fi

    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

# $1: 实例名  $2: follow(非空则用 -f 持续跟随，否则只看最后1000行)  $3: silent
log() {
    local name="$1"
    local follow="$2"
    local silent="$3"
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if [[ -n "$follow" ]]; then
        journalctl -u "$(instance_service_name "$name").service" -e --no-pager -f
    else
        journalctl -u "$(instance_service_name "$name").service" -n 1000 --no-pager
    fi
    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/v2node -N --no-check-certificate https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/v2node.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2node
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
# $1 (可选): 实例名，省略时查默认实例
check_status() {
    local instance="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        local init=$(instance_init_name "$instance")
        if [[ -n "$instance" && ! -e /etc/init.d/${init} ]]; then
            return 2
        fi
        temp=$(service ${init} status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        local svc=$(instance_service_name "$instance")
        if [[ -n "$instance" ]] && ! systemctl list-unit-files | grep -q "^${svc}\.service"; then
            return 2
        fi
        temp=$(systemctl status ${svc} | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# $1 (可选): 实例名，省略时查默认实例
check_enabled() {
    local instance="$1"
    if [[ x"${release}" == x"alpine" ]]; then
        local init=$(instance_init_name "$instance")
        temp=$(rc-update show 2>/dev/null | grep -E "^[[:space:]]*${init}[[:space:]]*\|")
        if [[ -z "$temp" ]]; then
            return 1
        else
            return 0
        fi
    else
        local svc=$(instance_service_name "$instance")
        temp=$(systemctl is-enabled "${svc}" 2>/dev/null)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}v2node已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装v2node${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# 列出默认实例 + 所有命名实例及各自状态（v2node list）
list() {
    echo "已知实例:"
    if [[ -f /etc/v2node/config.json ]]; then
        check_status ""
        case $? in
            0) echo -e "  default  (v2node.service): ${green}已运行${plain}" ;;
            1) echo -e "  default  (v2node.service): ${yellow}未运行${plain}" ;;
            *) echo -e "  default  (v2node.service): ${red}未知${plain}" ;;
        esac
    fi
    local d name
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            name=$(basename "$d")
            check_status "$name"
            case $? in
                0) echo -e "  ${name}  (v2node@${name}.service): ${green}已运行${plain}" ;;
                1) echo -e "  ${name}  (v2node@${name}.service): ${yellow}未运行${plain}" ;;
                *) echo -e "  ${name}  (v2node@${name}.service): ${red}未知${plain}" ;;
            esac
        done
    fi
}

# 在主菜单里列出命名实例（/etc/v2node/instances/ 下每个文件夹算一个）和各自
# 的运行状态，不用再进多实例子菜单才能看到；默认实例已经由 show_status 显示过
show_instances_status() {
    local d name has_any=0
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            has_any=1
            name=$(basename "$d")
            check_status "$name"
            case $? in
                0) echo -e "  实例 [${name}]: ${green}已运行${plain}" ;;
                1) echo -e "  实例 [${name}]: ${yellow}未运行${plain}" ;;
                *) echo -e "  实例 [${name}]: ${red}未知${plain}" ;;
            esac
        done
    fi
    if [[ $has_any == 0 ]]; then
        echo "  目前没有其他实例（可用菜单里的「管理多实例」新增）"
    fi
    echo "————————————————"
}

# 新建一个命名实例（v2node new <name>），交互式收集面板信息后委托给
# install.sh --instance 处理（下载/跳过下载共用二进制、写 service、生成配置）
new() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "请输入实例名(英文/数字，例如 nodeB): " name
    fi
    if [[ -z "$name" || "$name" == "config" ]]; then
        echo -e "${red}实例名不能为空${plain}"
        return 1
    fi
    if [[ -f "$(instance_config_path "$name")" ]]; then
        echo -e "${red}实例 [${name}] 已存在，如需修改配置请用: v2node config ${name}${plain}"
        return 1
    fi

    # 如果之前配置过其他实例（或默认实例），读上次用过的面板地址/密钥当
    # 默认值，直接回车即可沿用，不用每次都重新输入同一个面板的信息
    local last_host="" last_key=""
    [[ -f /etc/v2node/.last_api_host ]] && last_host=$(cat /etc/v2node/.last_api_host 2>/dev/null)
    [[ -f /etc/v2node/.last_api_key ]] && last_key=$(cat /etc/v2node/.last_api_key 2>/dev/null)

    read -rp "面板API地址[格式: https://example.com/]${last_host:+ [默认: $last_host]}: " api_host
    api_host=${api_host:-${last_host:-https://example.com/}}
    read -rp "节点ID: " node_id
    node_id=${node_id:-1}
    if [[ -n "$last_key" ]]; then
        read -rp "节点通讯密钥 [默认: ${last_key}]: " api_key
        api_key=${api_key:-$last_key}
    else
        read -rp "节点通讯密钥: " api_key
    fi
    node_type=$(choose_node_type)

    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) \
        --instance "$name" --api-host "$api_host" --node-id "$node_id" --api-key "$api_key" --node-type "$node_type"
}

# 移除一个或多个命名实例（v2node remove <name> [name...]），不影响默认实例
remove() {
    if [[ $# == 0 ]]; then
        echo -e "${red}请指定实例名: v2node remove <name> [name...]${plain}"
        return 1
    fi
    local name
    for name in "$@"; do
        [[ -z "$name" ]] && continue
        confirm "确定要移除实例 [${name}] 吗（不影响默认实例和其他实例）?" "n"
        if [[ $? != 0 ]]; then
            continue
        fi
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$name") stop 2>/dev/null
            rc-update del $(instance_init_name "$name") 2>/dev/null
            rm "/etc/init.d/$(instance_init_name "$name")" -f
        else
            systemctl stop "$(instance_service_name "$name")" 2>/dev/null
            systemctl disable "$(instance_service_name "$name")" 2>/dev/null
            systemctl reset-failed "$(instance_service_name "$name")" 2>/dev/null
        fi
        rm "$(instance_dir "$name")" -rf
        echo -e "${green}实例 [${name}] 已移除（共用的 v2node 主程序未受影响）${plain}"
    done
}

# 重命名一个命名实例（v2node rename <old> <new>），默认实例不支持重命名
rename() {
    local old="$1"
    local new_name="$2"
    if [[ -z "$old" || -z "$new_name" ]]; then
        echo -e "${red}用法: v2node rename <old_name> <new_name>${plain}"
        return 1
    fi
    if [[ ! -f "$(instance_config_path "$old")" ]]; then
        echo -e "${red}实例 [${old}] 不存在，或者它是默认实例（默认实例不支持重命名）${plain}"
        return 1
    fi
    if [[ -f "$(instance_config_path "$new_name")" ]]; then
        echo -e "${red}实例 [${new_name}] 已存在，换一个名字${plain}"
        return 1
    fi

    check_enabled "$old"
    local was_enabled=$?

    if [[ x"${release}" == x"alpine" ]]; then
        service $(instance_init_name "$old") stop 2>/dev/null
        rc-update del $(instance_init_name "$old") 2>/dev/null
        rm "/etc/init.d/$(instance_init_name "$old")" -f
    else
        systemctl stop "$(instance_service_name "$old")" 2>/dev/null
        systemctl disable "$(instance_service_name "$old")" 2>/dev/null
        systemctl reset-failed "$(instance_service_name "$old")" 2>/dev/null
    fi

    mv "$(instance_dir "$old")" "$(instance_dir "$new_name")"

    if [[ x"${release}" == x"alpine" ]]; then
        ln -sf /etc/init.d/v2node "/etc/init.d/$(instance_init_name "$new_name")"
        [[ $was_enabled == 0 ]] && rc-update add "$(instance_init_name "$new_name")" default
        service $(instance_init_name "$new_name") start
    else
        [[ $was_enabled == 0 ]] && systemctl enable "$(instance_service_name "$new_name")"
        systemctl start "$(instance_service_name "$new_name")"
    fi

    echo -e "${green}实例 [${old}] 已重命名为 [${new_name}]${plain}"
}

instance_menu() {
    echo -e "
  ${green}多实例管理${plain} — 在同一台机器再跑一个独立 v2node 进程
————————————————
  ${green}1.${plain} 列出已有实例
  ${green}2.${plain} 新增实例
  ${green}3.${plain} 移除实例
  ${green}4.${plain} 重命名实例
  ${green}5.${plain} 启动实例
  ${green}6.${plain} 停止实例
  ${green}7.${plain} 重启实例
  ${green}8.${plain} 查看实例状态
  ${green}9.${plain} 查看实例日志
  ${green}10.${plain} 设置实例开机自启
  ${green}11.${plain} 取消实例开机自启
  ${green}12.${plain} 编辑实例配置
  ${green}13.${plain} 返回主菜单
 "
    read -rp "请输入选择 [1-13]: " iop
    local iname="" iname2=""
    if [[ "$iop" != "1" && "$iop" != "2" && "$iop" != "3" && "$iop" != "13" ]]; then
        read -rp "实例名: " iname
    fi
    case "$iop" in
        1) list ;;
        2) new "" ;;
        3) read -rp "要移除的实例名(可空格分隔多个): " iname; remove $iname ;;
        4) read -rp "新名字: " iname2; rename "$iname" "$iname2" ;;
        5) start "$iname" 0 ;;
        6) stop "$iname" 0 ;;
        7) restart "$iname" 0 ;;
        8) status "$iname" 0 ;;
        9) log "$iname" "" 0 ;;
        10) enable "$iname" 0 ;;
        11) disable "$iname" 0 ;;
        12) config "$iname" 0 ;;
        13) show_menu; return ;;
        *) echo -e "${red}请输入正确的数字 [1-13]${plain}" ;;
    esac
    before_show_menu
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "v2node状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "v2node状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "v2node状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

show_v2node_version() {
    echo -n "v2node 版本："
    /usr/local/v2node/v2node version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

choose_node_type() {
    local options=("auto（由面板 API 自动判断协议，推荐）" "vmess" "vless" "trojan" "shadowsocks" "hysteria2" "tuic" "anytls" "mieru")
    local values=("v2node" "vmess" "vless" "trojan" "shadowsocks" "hysteria2" "tuic" "anytls" "mieru")
    echo "请选择节点类型:" >&2
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt" >&2
        i=$((i+1))
    done
    local choice
    while true; do
        read -rp "输入序号 [默认: 1) auto]: " choice
        choice=${choice:-1}
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#values[@]} )); then
            echo "${values[$((choice-1))]}"
            return 0
        fi
        echo "输入无效，请输入 1-${#values[@]} 之间的数字" >&2
    done
}

generate_v2node_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"
        local node_type="${4:-v2node}"

        mkdir -p /etc/v2node >/dev/null 2>&1
        cat > /etc/v2node/config.json <<EOF
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${node_id},
            "NodeType": "${node_type}",
            "ApiKey": "${api_key}",
            "Timeout": 15
        }
    ]
}
EOF
        # 记住这次用的面板地址/密钥，方便后续加实例时可以直接回车沿用
        echo -n "${api_host}" > /etc/v2node/.last_api_host
        echo -n "${api_key}" > /etc/v2node/.last_api_key

        echo -e "${green}V2node 配置文件生成完成,正在重新启动服务${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node restart
        else
            systemctl restart v2node
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node 重启成功${plain}"
        else
            echo -e "${red}v2node 可能启动失败，请使用 v2node log 查看日志信息${plain}"
        fi
}


generate_config_file() {
    # 交互式收集参数，如果之前配置过实例，读上次用过的面板地址/密钥当默认值
    local last_host="" last_key=""
    [[ -f /etc/v2node/.last_api_host ]] && last_host=$(cat /etc/v2node/.last_api_host 2>/dev/null)
    [[ -f /etc/v2node/.last_api_key ]] && last_key=$(cat /etc/v2node/.last_api_key 2>/dev/null)

    read -rp "面板API地址[格式: https://example.com/]${last_host:+ [默认: $last_host]}: " api_host
    api_host=${api_host:-${last_host:-https://example.com/}}
    read -rp "节点ID: " node_id
    node_id=${node_id:-1}
    if [[ -n "$last_key" ]]; then
        read -rp "节点通讯密钥 [默认: ${last_key}]: " api_key
        api_key=${api_key:-$last_key}
    else
        read -rp "节点通讯密钥: " api_key
    fi
    node_type=$(choose_node_type)

    generate_v2node_config "$api_host" "$node_id" "$api_key" "$node_type"
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "v2node 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "v2node                         - 显示管理菜单 (功能更多)"
    echo "v2node list                    - 列出已有实例及状态"
    echo "v2node new <name>              - 新建实例（交互式收集面板信息）"
    echo "v2node remove <name> [name...] - 移除实例"
    echo "v2node rename <old> <new>      - 重命名实例"
    echo "v2node start [name]            - 启动实例（省略实例名=默认实例）"
    echo "v2node stop [name]             - 停止实例"
    echo "v2node restart [name]          - 重启实例"
    echo "v2node status [name]           - 查看实例状态"
    echo "v2node enable [name]           - 设置实例开机自启"
    echo "v2node disable [name]          - 取消实例开机自启"
    echo "v2node log [name] [-f]         - 查看实例日志(默认最后1000行，-f 持续跟随)"
    echo "v2node config [name]           - 编辑实例配置并重启"
    echo "v2node generate                - 生成默认实例配置文件"
    echo "v2node update [version]        - 更新 v2node"
    echo "v2node install                 - 安装 v2node"
    echo "v2node uninstall               - 卸载 v2node（连同所有实例）"
    echo "v2node version                 - 查看 v2node 版本"
    echo "v2node update_shell            - 更新管理脚本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}v2node 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/wyusgw/v2node ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 v2node
  ${green}2.${plain} 更新 v2node
  ${green}3.${plain} 卸载 v2node
————————————————
  ${green}4.${plain} 启动 v2node
  ${green}5.${plain} 停止 v2node
  ${green}6.${plain} 重启 v2node
  ${green}7.${plain} 查看 v2node 状态
  ${green}8.${plain} 查看 v2node 日志
————————————————
  ${green}9.${plain} 设置 v2node 开机自启
  ${green}10.${plain} 取消 v2node 开机自启
————————————————
  ${green}11.${plain} 查看 v2node 版本
  ${green}12.${plain} 升级 v2node 维护脚本
  ${green}13.${plain} 生成 v2node 配置文件
  ${green}14.${plain} 放行 VPS 的所有网络端口
  ${green}15.${plain} 管理多实例（在本机再跑一个独立 v2node 进程）
  ${green}16.${plain} 退出脚本
 "
 #后续更新可加入上方字符串中
    show_status
    show_instances_status
    echo && read -rp "请输入选择 [0-16]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) check_install && show_v2node_version ;;
        12) update_shell ;;
        13) generate_config_file ;;
        14) open_ports ;;
        15) check_install && instance_menu ;;
        16) exit ;;
        *) echo -e "${red}请输入正确的数字 [0-16]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start "$2" 0 ;;
        "stop") check_install 0 && stop "$2" 0 ;;
        "restart") check_install 0 && restart "$2" 0 ;;
        "status") check_install 0 && status "$2" 0 ;;
        "enable") check_install 0 && enable "$2" 0 ;;
        "disable") check_install 0 && disable "$2" 0 ;;
        "log")
            log_follow=""
            log_name=""
            for log_arg in "$2" "$3"; do
                if [[ "$log_arg" == "-f" ]]; then
                    log_follow="1"
                elif [[ -n "$log_arg" ]]; then
                    log_name="$log_arg"
                fi
            done
            check_install 0 && log "$log_name" "$log_follow" 0
            ;;
        "config") check_install 0 && config "$2" 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "new") new "$2" ;;
        "remove") check_install 0 && remove "${@:2}" ;;
        "rename") check_install 0 && rename "$2" "$3" ;;
        "list") check_install 0 && list ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "version") check_install 0 && show_v2node_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
