#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

SCRIPT_VERSION="1.0.1"

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

is_cmd_exist() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 1
    fi
    which "$cmd" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        return 0
    fi
    return 2
}

# An empty instance name is the default instance (/etc/v2node/config.json, v2node.service)
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

# Panel defaults come from the newest instance config, so the key is not stored twice
load_panel_defaults() {
    last_host=""
    last_key=""
    local f
    f=$(ls -t /etc/v2node/config.json /etc/v2node/instances/*/config.json 2>/dev/null | head -1)
    [[ -n "$f" ]] || return 0
    last_host=$(sed -n 's/.*"ApiHost"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
    last_key=$(sed -n 's/.*"ApiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
}

mask_key() {
    local k="$1"
    if (( ${#k} > 8 )); then
        echo "${k:0:3}***${k: -3}"
    else
        echo "***"
    fi
}

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

instance_label() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "实例 [$1]"
    fi
}

instance_display_name() {
    if [[ -z "$1" ]]; then
        echo "default"
    else
        echo "$1"
    fi
}

CHANNEL_FILE="/etc/v2node/.channel"

get_channel() {
    if [[ -f "$CHANNEL_FILE" ]]; then
        cat "$CHANNEL_FILE"
    else
        echo "stable"
    fi
}

channel_label() {
    if [[ "$(get_channel)" == "beta" ]]; then
        echo "测试版"
    else
        echo "稳定版"
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

# Only waits for Enter: calling show_menu here would grow the call stack until bash exits
before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
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

# The releases feed is not rate limited, so it is tried first; links may encode + as %2B.
# With "all" the API comes first: the feed holds only the newest few releases.
list_release_tags() {
    local list="" api="https://api.github.com/repos/wyusgw/v2node/releases?per_page=100"
    local feed="https://github.com/wyusgw/v2node/releases.atom"
    if [[ "$1" == "all" ]]; then
        list=$(curl -Ls --connect-timeout 3 --max-time 8 "$api" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    if [[ -z "$list" ]]; then
        list=$(curl -Ls --connect-timeout 3 --max-time 6 "$feed" 2>/dev/null | grep -o 'releases/tag/[^"<]*' | sed 's#releases/tag/##; s/%2[Bb]/+/g' | awk '!seen[$0]++')
    fi
    if [[ -z "$list" && "$1" != "all" ]]; then
        list=$(curl -Ls --connect-timeout 3 --max-time 6 "$api" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    echo "$list"
}

list_release_versions() {
    local scope="$1" keyword="$2" tags list
    tags=$(list_release_tags "$scope")
    if [[ "$(get_channel)" == "beta" ]]; then
        list=$(echo "$tags" | grep -E '^[vV]?[0-9]' | grep -vE '^[vV]?[0-9]+(\.[0-9]+)*$')
    else
        list=$(echo "$tags" | grep -E '^[vV]?[0-9]+(\.[0-9]+)*$')
    fi
    list=$(echo "$list" | awk 'NF && !seen[$0]++')
    if [[ -n "$keyword" ]]; then
        list=$(echo "$list" | grep -iF -- "$keyword")
    fi
    if [[ "$scope" != "all" ]]; then
        list=$(echo "$list" | head -15)
    fi
    [[ -n "$list" ]] && echo "$list"
}

print_version_list() {
    local installed="$1" i mark label
    shift
    local versions=("$@")
    for i in "${!versions[@]}"; do
        label="${versions[$i]}"
        mark=""
        if [[ -n "$installed" && "${label#[vV]}" == "${installed#[vV]}" ]]; then
            mark="  ${green}<- 当前版本${plain}"
        elif [[ $i -eq 0 && -z "$searching" ]]; then
            mark="  <- 最新"
        fi
        echo -e "  $((i + 1)). ${label}${mark}"
    done
}

choose_update_version() {
    chosen_version=""
    searching=""
    local installed="" list=() line
    if [[ -f /usr/local/v2node/v2node ]]; then
        installed=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    fi
    echo -e "\n正在获取可用版本..."
    while IFS= read -r line; do
        [[ -n "$line" ]] && list+=("$line")
    done < <(list_release_versions)
    if [[ ${#list[@]} -eq 0 ]]; then
        echo -e "${yellow}获取版本列表失败，请检查本机能否连接 Github，可直接手动输入版本号${plain}"
    else
        echo -e "$(channel_label)可更新的版本(当前: ${installed:-未安装})"
        print_version_list "$installed" "${list[@]}"
    fi
    echo -e "提示: 输入关键词搜索$(channel_label)的全部版本(如0.1)只输入 / 列出全部"
    local input keyword found newest="${list[0]}"
    while true; do
        read -rp "输入序号或关键词搜索直接回车(最新版): " input
        if [[ -z "$input" ]]; then
            if [[ "$(get_channel)" == "beta" && -n "$newest" ]]; then
                chosen_version="$newest"
                break
            fi
            return 0
        elif [[ ! "$input" =~ ^[0-9]+$ ]]; then
            keyword="${input#/}"
            keyword="${keyword#"${keyword%%[![:space:]]*}"}"
            keyword="${keyword%"${keyword##*[![:space:]]}"}"
            echo -e "正在搜索..."
            found=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && found+=("$line")
            done < <(list_release_versions all "$keyword")
            if [[ ${#found[@]} -eq 0 ]]; then
                echo -e "${yellow}$(channel_label)没有${keyword:+包含 \"${keyword}\" 的}版本，请换个关键词${plain}"
                continue
            fi
            list=("${found[@]}")
            searching=1
            if [[ -n "$keyword" ]]; then
                echo -e "$(channel_label)中包含 \"${keyword}\" 的版本（共 ${#list[@]} 个）:"
            else
                echo -e "$(channel_label)全部版本（共 ${#list[@]} 个）:"
            fi
            print_version_list "$installed" "${list[@]}"
            searching=""
        elif [[ "$input" =~ ^[0-9]+$ ]]; then
            if (( input >= 1 && input <= ${#list[@]} )); then
                chosen_version="${list[$((input - 1))]}"
                break
            fi
            echo -e "${red}序号超出范围，请重新输入${plain}"
        fi
    done
}

update() {
    local version
    if [[ $# == 0 ]]; then
        choose_update_version
        version="$chosen_version"
        # Looked up fresh rather than from the menu's cache, which can be stale
        local installed="" latest target
        if [[ -f /usr/local/v2node/v2node ]]; then
            installed=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
        fi
        if [[ -n "$installed" ]]; then
            latest=$(fetch_latest_version)
            target="${version:-$latest}"
            if [[ -n "$latest" && "${target#[vV]}" == "${latest#[vV]}" && "${installed#[vV]}" == "${latest#[vV]}" ]]; then
                echo -e "${green}当前版本 ${installed} 已是最新版本${plain}"
                before_show_menu
                return 0
            fi
        fi
        echo -e "将安装版本: ${green}${version:-最新版}${plain}"
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) $version
    if [[ $? == 0 ]]; then
        # install.sh restarts only the default instance; restart the running named ones
        local named=() d
        if [[ -d /etc/v2node/instances ]]; then
            for d in /etc/v2node/instances/*/; do
                [[ -e "$d" ]] && named+=("$(basename "$d")")
            done
        fi
        if [[ ${#named[@]} -eq 0 ]]; then
            echo -e "${green}更新完成，请使用 v2node log 查看运行日志${plain}"
        else
            echo -e "${green}更新完成，请使用 v2node log [实例名] 查看运行日志（省略实例名即默认实例）${plain}"
        fi
        local n stopped=()
        for n in "${named[@]}"; do
            if check_status "$n"; then
                restart "$n" silent
            else
                stopped+=("$n")
            fi
        done
        if [[ ${#stopped[@]} -gt 0 ]]; then
            echo -e "${yellow}命名实例 [${stopped[*]}] 当前未运行，未自动启动，下次启动时会用上新版本${plain}"
        fi
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

switch_channel() {
    local silent="$1"
    local cur target target_label
    cur=$(get_channel)
    target="beta"
    target_label="测试版"
    if [[ "$cur" == "beta" ]]; then
        target="stable"
        target_label="稳定版"
    fi
    echo -e "当前安装分支: $(channel_label)"
    if [[ "$target" == "beta" ]]; then
        echo -e "${yellow}测试版是 dev 分支的滚动构建，可能不稳定，仅建议在测试环境使用${plain}"
    fi
    confirm "确定要切换到${target_label}吗" "n"
    if [[ $? != 0 ]]; then
        [[ -z "$silent" ]] && before_show_menu
        return 0
    fi
    mkdir -p /etc/v2node
    echo "$target" > "$CHANNEL_FILE"
    echo -e "${green}已切换到${target_label}${plain}，下次安装/更新会使用这个分支"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        [[ -z "$silent" ]] && before_show_menu
        return 0
    fi
    confirm "是否立即按新分支重新安装/更新 v2node" "y"
    if [[ $? == 0 ]]; then
        update 0 ""
    fi
    [[ -z "$silent" ]] && before_show_menu
}

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

uninstall() {
    confirm "确定要卸载 v2node 吗（会连同所有实例一起移除）?" "n"
    if [[ $? != 0 ]]; then
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

# The program reloads on writes to its config file, so rewriting it in place reloads it
reload_config() {
    local name="$1"
    local silent="$2"
    local cfg=$(instance_config_path "$name")
    if [[ ! -f "$cfg" ]]; then
        echo -e "${red}$(instance_label "$name") 还没有配置文件${plain}"
    else
        local tmp
        tmp=$(mktemp) && cat "$cfg" > "$tmp" && cat "$tmp" > "$cfg"
        rm -f "$tmp"
        echo -e "${green}已触发$(instance_label "$name")重载配置，约 5 秒后生效，可用 v2node log${name:+ $name} 查看${plain}"
    fi
    if [[ -z "$silent" ]]; then before_show_menu; fi
}

quick_config() {
    local name="$1"
    local silent="$2"
    local cfg=$(instance_config_path "$name")
    if [[ ! -f "$cfg" ]]; then
        echo -e "${red}$(instance_label "$name") 还没有配置文件${plain}"
        [[ -n "$name" ]] && echo -e "${yellow}请先执行: v2node new ${name}${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if (( $(grep -c '"NodeID"' "$cfg") != 1 )); then
        echo -e "${red}$(instance_label "$name") 的配置里有多个节点，快速配置只支持单节点，请用「编辑配置」修改${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi

    local cur_host cur_id cur_key cur_type
    cur_host=$(sed -n 's/.*"ApiHost"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -1)
    cur_id=$(sed -n 's/.*"NodeID"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$cfg" | head -1)
    cur_key=$(sed -n 's/.*"ApiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -1)
    cur_type=$(sed -n 's/.*"NodeType"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -1)
    cur_type=${cur_type:-v2node}

    local api_host node_id api_key node_type
    read -rp "面板API地址 [当前: ${cur_host}]: " api_host
    api_host=${api_host:-$cur_host}
    read -rp "节点ID [当前: ${cur_id}]: " node_id
    node_id=${node_id:-$cur_id}
    read -rp "节点通讯密钥 [当前: $(mask_key "$cur_key")]: " api_key
    api_key=${api_key:-$cur_key}
    node_type=$(choose_node_type "$cur_type")

    if [[ ! "$node_id" =~ ^[0-9]+$ ]]; then
        echo -e "${red}节点ID必须是数字${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if [[ "$api_host$api_key" == *'"'* || "$api_host$api_key" == *'\'* ]]; then
        echo -e "${red}面板地址和密钥不能包含双引号或反斜杠${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi

    local e_host e_key
    e_host=$(printf '%s' "$api_host" | sed 's/[\\&|]/\\&/g')
    e_key=$(printf '%s' "$api_key" | sed 's/[\\&|]/\\&/g')
    sed -i \
        -e "s|\(\"ApiHost\"[[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\1\"${e_host}\"|" \
        -e "s|\(\"NodeID\"[[:space:]]*:[[:space:]]*\)[0-9]*|\1${node_id}|" \
        -e "s|\(\"ApiKey\"[[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\1\"${e_key}\"|" \
        "$cfg"
    if grep -q '"NodeType"' "$cfg"; then
        sed -i "s|\(\"NodeType\"[[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\1\"${node_type}\"|" "$cfg"
    else
        local tmp
        tmp=$(mktemp) && awk -v t="$node_type" '{ print } /"NodeID"/ && !done { print "            \"NodeType\": \"" t "\","; done = 1 }' "$cfg" > "$tmp" && cat "$tmp" > "$cfg"
        rm -f "$tmp"
    fi
    echo -e "${green}$(instance_label "$name") 配置已更新，正在重启${plain}"
    restart "$name" 0
    if [[ -z "$silent" ]]; then before_show_menu; fi
}

# Lifecycle functions take [instance] [silent]; silent skips returning to the menu

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

log() {
    local name="$1"
    local follow="$2"
    local silent="$3"
    local lines="$4"
    if [[ ! "$lines" =~ ^[0-9]+$ ]] || (( lines < 1 )); then
        lines=1000
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if [[ -n "$follow" ]]; then
        journalctl -u "$(instance_service_name "$name").service" -e --no-pager -f
    else
        journalctl -u "$(instance_service_name "$name").service" -n "$lines" --no-pager
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
check_status() {
    local instance="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    # Check the config file: template instances such as v2node@x are not in list-unit-files
    if [[ ! -f "$(instance_config_path "$instance")" ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        local init=$(instance_init_name "$instance")
        temp=$(service ${init} status 2>/dev/null | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        local svc=$(instance_service_name "$instance")
        # Not systemctl status, which reads the journal tail and is slow on large journals
        temp=$(systemctl show -p SubState "${svc}" 2>/dev/null | cut -d= -f2)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

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
    local instance="$1"
    local silent="$2"
    check_status "$instance"
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}$(instance_label "$instance") 还没有安装或配置${plain}"
        if [[ -z "$silent" ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_binary_install() {
    local silent="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        echo ""
        echo -e "${red}请先安装v2node${plain}"
        if [[ -z "$silent" ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

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

new() {
    local name="$1"
    local silent="$2"
    if [[ -z "$name" ]]; then
        read -rp "请输入实例名(英文/数字，例如 nodeB): " name
    fi
    if [[ -z "$name" || "$name" == "config" ]]; then
        echo -e "${red}实例名不能为空${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if [[ -f "$(instance_config_path "$name")" ]]; then
        echo -e "${red}实例 [${name}] 已存在，如需修改配置请用: v2node config ${name}${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi

    local last_host="" last_key=""
    load_panel_defaults

    read -rp "面板API地址[格式: https://example.com/]${last_host:+ [默认: $last_host]}: " api_host
    api_host=${api_host:-${last_host:-https://example.com/}}
    read -rp "节点ID: " node_id
    node_id=${node_id:-1}
    if [[ -n "$last_key" ]]; then
        read -rp "节点通讯密钥 [默认: $(mask_key "$last_key")]: " api_key
        api_key=${api_key:-$last_key}
    else
        read -rp "节点通讯密钥: " api_key
    fi
    node_type=$(choose_node_type)

    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) \
        --instance "$name" --api-host "$api_host" --node-id "$node_id" --api-key "$api_key" --node-type "$node_type"
    if [[ -z "$silent" ]]; then before_show_menu; fi
}

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
        echo -e "${green}实例 [${name}] 已移除${plain}"
    done
}

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

instance_submenu() {
    local name="$1"
    local max=13
    local status_text enable_text
    check_status "$name"
    case $? in
        0) status_text="${green}已运行${plain}" ;;
        1) status_text="${yellow}未运行${plain}" ;;
        *) status_text="${red}未安装${plain}" ;;
    esac
    check_enabled "$name"
    if [[ $? == 0 ]]; then enable_text="${green}是${plain}"; else enable_text="${red}否${plain}"; fi
    echo -e "
  ${green}v2node [$(instance_display_name "$name")] 管理${plain}

  状态: ${status_text}    自启: ${enable_text}
  配置: $(instance_config_path "$name")

  ${green}0.${plain} 返回上级
————————————————
  ${green}1.${plain} 启动
  ${green}2.${plain} 停止
  ${green}3.${plain} 重启
  ${green}4.${plain} 重载配置
————————————————
  ${green}5.${plain} 查看服务状态详情
  ${green}6.${plain} 查看最近日志
  ${green}7.${plain} 持续输出日志
————————————————
  ${green}8.${plain} 设置开机自启
  ${green}9.${plain} 取消开机自启
————————————————
  ${green}10.${plain} 快速配置
  ${green}11.${plain} 编辑配置"
    if [[ -n "$name" ]]; then
        echo -e "————————————————
  ${green}12.${plain} 重命名此实例
  ${green}13.${plain} 移除此实例"
    else
        max=11
    fi
    echo " "
    read -rp "请输入选择 [0-${max}]: " iop
    case "$iop" in
        0) return ;;
        1) start "$name" 0 ;;
        2) stop "$name" 0 ;;
        3) restart "$name" 0 ;;
        4) reload_config "$name" 0 ;;
        5) status "$name" 0 ;;
        6)
            read -rp "查看最近多少行日志 [默认: 1000]: " log_lines
            log "$name" "" 0 "$log_lines"
            ;;
        7) log "$name" "1" 0 ;;
        8) enable "$name" 0 ;;
        9) disable "$name" 0 ;;
        10) quick_config "$name" 0 ;;
        11) config "$name" 0 ;;
        12)
            if [[ -n "$name" ]]; then
                read -rp "新名字: " new_name
                rename "$name" "$new_name"
            else
                echo -e "${red}默认实例不支持重命名${plain}"
            fi
            ;;
        13)
            if [[ -n "$name" ]]; then
                remove "$name"
            else
                echo -e "${red}默认实例不支持移除，请用「完全卸载」${plain}"
            fi
            ;;
        *) echo -e "${red}请输入正确的数字 [0-${max}]${plain}" ;;
    esac
    before_show_menu
}

# Short timeouts so an unreachable GitHub cannot hang the menu
fetch_latest_version() {
    local latest
    if [[ "$(get_channel)" == "beta" ]]; then
        latest=$(list_release_versions | head -1)
    else
        latest=$(curl -Ls --connect-timeout 2 --max-time 4 "https://api.github.com/repos/wyusgw/v2node/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$latest" ]]; then
            latest=$(curl -sIL -o /dev/null -w '%{url_effective}' --connect-timeout 2 --max-time 4 "https://github.com/wyusgw/v2node/releases/latest" 2>/dev/null | sed -n 's#.*/releases/tag/##p')
        fi
    fi
    echo "$latest"
}

# Cached for 30 minutes; a failed lookup waits 5 minutes before the next try
get_latest_version() {
    local dir="/run"
    [[ -d "$dir" && -w "$dir" ]] || dir="/tmp"
    local cache="${dir}/.v2node_latest_$(get_channel)"
    local fail="${cache}.fail"
    if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +30 2>/dev/null)" ]]; then
        if [[ -z "$(find "$fail" -mmin -5 2>/dev/null)" ]]; then
            local latest
            latest=$(fetch_latest_version)
            if [[ -n "$latest" ]]; then
                echo "$latest" > "${cache}.tmp" && mv -f "${cache}.tmp" "$cache"
                rm -f "$fail"
            else
                touch "$fail" 2>/dev/null
            fi
        fi
    fi
    [[ -s "$cache" ]] && cat "$cache"
}

# Non-numeric versions such as beta-<commit> fall back to "different means newer"
version_is_newer() {
    local a="${1#[vV]}" b="${2#[vV]}"
    [[ "$a" == "$b" ]] && return 1
    if [[ ! "$a" =~ ^[0-9]+(\.[0-9]+)*$ || ! "$b" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        return 0
    fi
    local -a pa pb
    IFS=. read -ra pa <<< "$a"
    IFS=. read -ra pb <<< "$b"
    local i n=${#pa[@]}
    (( ${#pb[@]} > n )) && n=${#pb[@]}
    for (( i = 0; i < n; i++ )); do
        local x=$((10#${pa[i]:-0})) y=$((10#${pb[i]:-0}))
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 1
}

# Compared by checksum, so a change without a SCRIPT_VERSION bump is still noticed
script_has_update() {
    [[ -f /usr/bin/v2node ]] || return 1
    local dir="/run"
    [[ -d "$dir" && -w "$dir" ]] || dir="/tmp"
    local cache="${dir}/.v2node_script_sha256"
    local fail="${cache}.fail"
    if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +30 2>/dev/null)" ]]; then
        if [[ -z "$(find "$fail" -mmin -5 2>/dev/null)" ]]; then
            local tmp
            tmp=$(mktemp 2>/dev/null) || return 1
            curl -Ls --connect-timeout 2 --max-time 6 -o "$tmp" "https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/v2node.sh" 2>/dev/null
            # A real copy starts with the shebang; anything else is an error page or a cut download
            if [[ "$(head -c 2 "$tmp" 2>/dev/null)" == "#!" && $(wc -c < "$tmp") -gt 1000 ]]; then
                # line 1: checksum, line 2: the copy's SCRIPT_VERSION
                {
                    sha256sum "$tmp" | awk '{print $1}'
                    grep -m1 '^SCRIPT_VERSION=' "$tmp" | sed -E 's/^SCRIPT_VERSION="?([^"]*)"?.*/\1/'
                } > "${cache}.tmp" && mv -f "${cache}.tmp" "$cache"
                rm -f "$fail"
            else
                touch "$fail" 2>/dev/null
            fi
            rm -f "$tmp"
        fi
    fi
    [[ -s "$cache" ]] || return 1
    [[ "$(head -1 "$cache")" != "$(sha256sum /usr/bin/v2node | awk '{print $1}')" ]] || return 1
    sed -n 2p "$cache"
}

show_version_header() {
    local installed=""
    if [[ -f /usr/local/v2node/v2node ]]; then
        installed=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    fi
    if [[ -n "$installed" ]]; then
        echo -e "  ${green}v2node 管理脚本 v${SCRIPT_VERSION}${plain}  [v2node: ${installed}]  [分支: $(channel_label)]"
        local latest
        latest=$(get_latest_version)
        if [[ -n "$latest" ]] && version_is_newer "$latest" "$installed"; then
            echo -e "  ${yellow}发现新版本: v2node ${latest}${plain}"
        fi
    else
        echo -e "  ${green}v2node 管理脚本 v${SCRIPT_VERSION}${plain}  [v2node: 未安装]  [分支: $(channel_label)]"
    fi
    local script_latest
    if script_latest=$(script_has_update); then
        if [[ -n "$script_latest" && "$script_latest" != "$SCRIPT_VERSION" ]]; then
            echo -e "  ${yellow}发现管理脚本新版本: v${script_latest}${plain}"
        else
            echo -e "  ${yellow}发现管理脚本新版本${plain}"
        fi
    fi
}

show_instance_list() {
    echo ""
    echo "  实例列表:"
    local status_text enable_text
    if [[ -f /etc/v2node/config.json ]]; then
        check_status ""
        case $? in
            0) status_text="${green}已运行${plain}" ;;
            1) status_text="${yellow}未运行${plain}" ;;
            *) status_text="${red}未安装${plain}" ;;
        esac
        check_enabled ""
        if [[ $? == 0 ]]; then enable_text="${green}是${plain}"; else enable_text="${red}否${plain}"; fi
        printf "    %-12s [%b] [自启: %b]  %s\n" "default" "$status_text" "$enable_text" "/etc/v2node/config.json"
    fi

    local d name
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            name=$(basename "$d")
            check_status "$name"
            case $? in
                0) status_text="${green}已运行${plain}" ;;
                1) status_text="${yellow}未运行${plain}" ;;
                *) status_text="${red}未安装${plain}" ;;
            esac
            check_enabled "$name"
            if [[ $? == 0 ]]; then enable_text="${green}是${plain}"; else enable_text="${red}否${plain}"; fi
            printf "    %-12s [%b] [自启: %b]  %s\n" "$name" "$status_text" "$enable_text" "$(instance_config_path "$name")"
        done
    fi
}

install_or_update() {
    # check_status "" sees only the default instance; a fresh install would wipe the shared binary
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        install
    else
        update
    fi
}

show_v2node_version() {
    local installed=""
    if [[ -f /usr/local/v2node/v2node ]]; then
        installed=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    fi
    echo -e "管理脚本版本: ${green}v${SCRIPT_VERSION}${plain}"
    echo -e "安装分支:     $(channel_label)"
    if [[ -z "$installed" ]]; then
        echo -e "已安装版本:   ${yellow}未安装${plain}"
    else
        echo -e "已安装版本:   ${green}${installed}${plain}"
    fi
    echo -n "最新版本:     "
    local latest
    latest=$(fetch_latest_version)
    if [[ -z "$latest" ]]; then
        echo -e "${yellow}查询失败，请检查本机能否连接 Github${plain}"
    else
        echo -e "${latest}"
        local dir="/run"
        [[ -d "$dir" && -w "$dir" ]] || dir="/tmp"
        echo "$latest" > "${dir}/.v2node_latest_$(get_channel)" 2>/dev/null
        if [[ -n "$installed" ]]; then
            if version_is_newer "$latest" "$installed"; then
                echo -e "${yellow}有新版本可更新${plain}"
            else
                echo -e "${green}已是最新版本${plain}"
            fi
        fi
    fi
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
    local choice default_idx=1 j
    for j in "${!values[@]}"; do
        [[ "${values[$j]}" == "$1" ]] && default_idx=$((j+1))
    done
    while true; do
        read -rp "输入序号 [默认: ${default_idx}) ${values[$((default_idx-1))]}]: " choice
        choice=${choice:-$default_idx}
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
        local instance="$5"

        mkdir -p "$(instance_dir "$instance")" >/dev/null 2>&1
        cat > "$(instance_config_path "$instance")" <<EOF
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
        echo -e "${green}$(instance_label "$instance") 配置文件生成完成,正在重新启动服务${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$instance") restart
        else
            systemctl restart "$(instance_service_name "$instance")"
        fi
        sleep 2
        check_status "$instance"
        local started=$?
        echo -e ""
        if [[ $started == 0 ]]; then
            echo -e "${green}$(instance_label "$instance") 重启成功${plain}"
        else
            echo -e "${red}$(instance_label "$instance") 可能启动失败，请使用 v2node log${instance:+ $instance} 查看日志信息${plain}"
        fi
}


generate_config_file() {
    local last_host="" last_key=""
    load_panel_defaults

    read -rp "面板API地址[格式: https://example.com/]${last_host:+ [默认: $last_host]}: " api_host
    api_host=${api_host:-${last_host:-https://example.com/}}
    read -rp "节点ID: " node_id
    node_id=${node_id:-1}
    if [[ -n "$last_key" ]]; then
        read -rp "节点通讯密钥 [默认: $(mask_key "$last_key")]: " api_key
        api_key=${api_key:-$last_key}
    else
        read -rp "节点通讯密钥: " api_key
    fi
    node_type=$(choose_node_type)

    generate_v2node_config "$api_host" "$node_id" "$api_key" "$node_type"
}

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
    echo "----------------------------------------------------------"
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
    echo "v2node log [name] [-n 行数] [-f] - 查看实例日志(默认最后1000行，-n 自定义行数，-f 持续跟随)"
    echo "v2node config [name]           - 编辑实例配置并重启"
    echo "v2node reload [name]           - 重载实例配置（不重启进程）"
    echo "v2node quick [name]            - 快速配置实例（面板地址/节点ID/密钥/节点类型）"
    echo "v2node generate                - 生成默认实例配置文件"
    echo "v2node update [version]        - 更新 v2node（不带版本号时列出当前分支的版本，输入序号选择或关键词搜索，回车=最新版）"
    echo "v2node install                 - 安装 v2node"
    echo "v2node uninstall               - 卸载 v2node（连同所有实例）"
    echo "v2node version                 - 查看版本信息（管理脚本/已安装/最新）"
    echo "v2node channel [stable|beta]   - 查看/切换安装分支（不带参数=查看当前分支）"
    echo "v2node update_shell            - 更新管理脚本"
    echo "----------------------------------------------------------"
}

show_menu() {
    show_version_header
    echo -e "
  ${green}0.${plain} 退出
————————————————
  ${green}1.${plain} 安装/更新 v2node
  ${green}2.${plain} 完全卸载 v2node
————————————————
  ${green}3.${plain} 更新管理脚本
  ${green}4.${plain} 切换安装分支 [当前: $(channel_label)]
  ${green}5.${plain} 新增 v2node 实例
  ${green}6.${plain} 查看版本
————————————————"

    local menu_instances=()
    if [[ -f /etc/v2node/config.json ]]; then
        menu_instances+=("")
    fi
    local d
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            menu_instances+=("$(basename "$d")")
        done
    fi
    local i num_i=7
    for i in "${menu_instances[@]}"; do
        echo -e "  ${green}${num_i}.${plain} 管理实例 [$(instance_display_name "$i")]"
        num_i=$((num_i + 1))
    done
    echo " "
    show_instance_list
    local max=$((7 + ${#menu_instances[@]} - 1))
    echo && read -rp "请输入选择 [0-${max}] 或 [实例名]: " num

    case "${num}" in
        0|"") echo -e "${red}请输入选择 [0-${max}]${plain}" && exit ;;
        1) install_or_update ;;
        2) check_binary_install && uninstall ;;
        3) update_shell ;;
        4) switch_channel ;;
        5) new "" ;;
        6) show_v2node_version ;;
        *)
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 7 && num < 7 + ${#menu_instances[@]} )); then
                local picked="${menu_instances[$((num - 7))]}"
                check_install "$picked" && instance_submenu "$picked"
            elif [[ "$num" == "default" ]] || [[ -f "$(instance_config_path "$num")" ]]; then
                local picked=""
                [[ "$num" != "default" ]] && picked="$num"
                check_install "$picked" && instance_submenu "$picked"
            else
                echo -e "${red}请输入正确的数字 [0-${max}]，或是一个存在的实例名${plain}"
                before_show_menu
            fi
            ;;
    esac
}

if [[ x"${release}" != x"alpine" ]]; then
    is_cmd_exist "systemctl"
    if [[ $? != 0 ]]; then
        echo -e "${red}systemctl 命令不存在，请使用较新版本的系统，例如 Ubuntu 18+、Debian 9+${plain}"
        exit 1
    fi
fi

if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install "$2" 0 && start "$2" 0 ;;
        "stop") check_install "$2" 0 && stop "$2" 0 ;;
        "restart") check_install "$2" 0 && restart "$2" 0 ;;
        "status") check_install "$2" 0 && status "$2" 0 ;;
        "enable") check_install "$2" 0 && enable "$2" 0 ;;
        "disable") check_install "$2" 0 && disable "$2" 0 ;;
        "log")
            log_follow=""
            log_name=""
            log_lines=""
            log_args=("${@:2}")
            for ((log_i = 0; log_i < ${#log_args[@]}; log_i++)); do
                log_arg="${log_args[$log_i]}"
                if [[ "$log_arg" == "-f" ]]; then
                    log_follow="1"
                elif [[ "$log_arg" == "-n" ]]; then
                    log_i=$((log_i + 1))
                    log_lines="${log_args[$log_i]}"
                elif [[ -n "$log_arg" ]]; then
                    log_name="$log_arg"
                fi
            done
            check_install "$log_name" 0 && log "$log_name" "$log_follow" 0 "$log_lines"
            ;;
        "config") check_install "$2" 0 && config "$2" 0 ;;
        "reload") check_install "$2" 0 && reload_config "$2" 0 ;;
        "quick") check_install "$2" 0 && quick_config "$2" 0 ;;
        "update")
            if check_binary_install 0; then
                # On a terminal without a version, list versions; scripts update to the latest
                if [[ -z "$2" && -t 0 ]]; then
                    choose_update_version
                    update 0 "$chosen_version"
                else
                    update 0 "$2"
                fi
            fi
            ;;
        "new") new "$2" 0 ;;
        "remove") check_install "$2" 0 && remove "${@:2}" ;;
        "rename") check_install "$2" 0 && rename "$2" "$3" ;;
        "list") check_binary_install 0 && list ;;
        "generate") generate_config_file ;;
        "open_ports") open_ports ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_binary_install 0 && uninstall 0 ;;
        "version") check_binary_install 0 && show_v2node_version 0 ;;
        "update_shell") update_shell ;;
        "channel")
            if [[ -z "$2" ]]; then
                echo "当前安装分支: $(channel_label)"
            elif [[ "$2" == "stable" || "$2" == "beta" ]]; then
                mkdir -p /etc/v2node
                echo "$2" > "$CHANNEL_FILE"
                echo -e "${green}已切换到$(channel_label)${plain}，下次安装/更新会使用这个分支，执行 v2node update 立即生效"
            else
                echo -e "${red}未知分支: $2，只能是 stable 或 beta${plain}"
            fi
            ;;
        *) show_usage
    esac
else
    # This loop redraws the menu; menu functions never call each other recursively
    while true; do
        show_menu
    done
fi
