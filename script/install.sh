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

########################
# 参数解析
########################
VERSION_ARG=""
API_HOST_ARG=""
NODE_ID_ARG=""
NODE_TYPE_ARG=""
API_KEY_ARG=""
INSTANCE_ARG=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)
                API_HOST_ARG="$2"; shift 2 ;;
            --node-id)
                NODE_ID_ARG="$2"; shift 2 ;;
            --node-type)
                NODE_TYPE_ARG="$2"; shift 2 ;;
            --api-key)
                API_KEY_ARG="$2"; shift 2 ;;
            --instance)
                INSTANCE_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "用法: $0 [版本号] [--api-host URL] [--node-id ID] [--api-key KEY] [--node-type TYPE] [--instance NAME]"
                echo "--node-type 可省略：省略时协议由面板 API 自动判断（对应后台的 v2node 节点类型）"
                echo "如需固定为某个协议专属表，可指定：vmess / vless / trojan / shadowsocks / hysteria2 / tuic / anytls / mieru"
                echo "--instance 可省略：省略时安装/更新默认实例（/etc/v2node/config.json，v2node.service）"
                echo "如需在同一台机器上再跑一个完全独立的 v2node 进程，指定一个实例名，例如 --instance nodeB"
                echo "（会生成 /etc/v2node/nodeB.json，用 systemctl 管理 v2node@nodeB.service，不影响默认实例）"
                exit 0 ;;
            --*)
                echo "未知参数: $1"; exit 1 ;;
            *)
                # 兼容第一个位置参数作为版本号
                if [[ -z "$VERSION_ARG" ]]; then
                    VERSION_ARG="$1"; shift
                else
                    shift
                fi ;;
        esac
    done
}

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

# 实例名为空时对应原本的默认实例（/etc/v2node/config.json, v2node.service），
# 保证没有用到 --instance 的既有用法完全不受影响
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

# 命名实例各自一个文件夹（/etc/v2node/instances/<name>/），方便直接靠目录
# 列表枚举有哪些实例；默认实例沿用原本的 /etc/v2node/config.json，不进文件夹
instance_dir() {
    if [[ -z "$1" ]]; then
        echo "/etc/v2node"
    else
        echo "/etc/v2node/instances/$1"
    fi
}

# alpine openrc 没有 systemd 的 template unit，用「同一个脚本 + 不同文件名的
# symlink」实现多实例：openrc 会把脚本被调用时的文件名放进 $SVCNAME，脚本本身
# 再据此推出要读哪个实例的配置文件（见 install_v2node 里写入的 /etc/init.d/v2node）
instance_init_name() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "v2node.$1"
    fi
}

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

echo "系统: ${release}  架构: ${arch}"

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

install_base() {
    # 优化版本：批量检查和安装包，减少系统调用
    need_install_apt() {
        local packages=("$@")
        local missing=()
        
        # 批量检查已安装的包
        local installed_list=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_yum() {
        local packages=("$@")
        local missing=()
        
        # 批量检查已安装的包
        local installed_list=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            yum install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_apk() {
        local packages=("$@")
        local missing=()
        
        # 批量检查已安装的包
        local installed_list=$(apk info 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
        fi
    }

    # 一次性安装所有必需的包
    if [[ x"${release}" == x"centos" ]]; then
        # 检查并安装 epel-release
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo "安装 EPEL 源..."
            yum install -y epel-release >/dev/null 2>&1
        fi
        need_install_yum wget curl unzip tar cronie socat ca-certificates pv
        update-ca-trust force-enable >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"alpine" ]]; then
        need_install_apk wget curl unzip tar socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"debian" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"ubuntu" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"arch" ]]; then
        echo "更新包数据库..."
        pacman -Sy --noconfirm >/dev/null 2>&1
        # --needed 会跳过已安装的包，非常高效
        echo "安装必需的包..."
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates pv >/dev/null 2>&1
    fi
}

# 0: running, 1: not running, 2: not installed
# $1 (可选): 实例名，省略时查默认实例
check_status() {
    local instance="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    # 用配置文件是否存在判断这个实例有没有配置过，而不是去 grep
    # systemctl list-unit-files——template unit 实例化出来的具体单元名
    # （如 v2node@test.service）通常不会出现在 list-unit-files 里，之前
    # 这样判断会导致命名实例明明装好在跑，却一直被判定成"未安装"
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
        temp=$(systemctl status ${svc} 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
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
        local instance="$5"
        local cfg=$(instance_config_path "$instance")
        local svc=$(instance_service_name "$instance")

        mkdir -p "$(instance_dir "$instance")" >/dev/null 2>&1
        cat > "$cfg" <<EOF
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
        # 记住这次用的面板地址/密钥，方便后续加实例时可以直接回车沿用，
        # 不用每次都重新输入同一个面板的信息
        echo -n "${api_host}" > /etc/v2node/.last_api_host
        echo -n "${api_key}" > /etc/v2node/.last_api_key

        echo -e "${green}v2node 配置文件(${cfg})生成完成,正在重新启动服务${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$instance") restart
        else
            systemctl restart "${svc}"
        fi
        sleep 2
        check_status "$instance"
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node 重启成功${plain}"
        else
            echo -e "${red}v2node 可能启动失败，请使用 v2node log 查看日志信息${plain}"
        fi
}

install_v2node() {
    local version_param="$1"
    local instance="$INSTANCE_ARG"
    local cfg=$(instance_config_path "$instance")
    local svc=$(instance_service_name "$instance")

    # 加实例时如果主程序已经装好了，就不要重新下载/解压——那会把正在跑的
    # 默认实例（或其他已存在实例）用的那份二进制文件从脚下抽掉。二进制、
    # geoip/geosite 是所有实例共用的一份，只有配置和 service 是各实例独立的。
    if [[ -n "$instance" && -f /usr/local/v2node/v2node ]]; then
        echo -e "${green}检测到 v2node 主程序已安装，跳过重新下载，仅为实例 [${instance}] 配置服务${plain}"
        last_version=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    else
    if [[ -e /usr/local/v2node/ ]]; then
        rm -rf /usr/local/v2node/
    fi

    mkdir /usr/local/v2node/ -p
    cd /usr/local/v2node/

    if  [[ -z "$version_param" ]] ; then
        last_version=$(curl -Ls "https://api.github.com/repos/wyusgw/v2node/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 v2node 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 v2node 版本安装${plain}"
            exit 1
        fi
        echo -e "${green}检测到最新版本：${last_version}，开始安装...${plain}"
        url="https://github.com/wyusgw/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "下载进度" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 v2node 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
    last_version=$version_param
        url="https://github.com/wyusgw/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "下载进度" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 v2node $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip v2node-linux.zip
    rm v2node-linux.zip -f
    chmod +x v2node
    mkdir /etc/v2node/ -p
    cp geoip.dat /etc/v2node/
    cp geosite.dat /etc/v2node/
    fi

    # service/init 脚本对所有实例都是共用同一份定义（systemd 的 template unit
    # 用 %i 代入实例名；openrc 用同一个脚本 + $SVCNAME 判断自己是哪个实例），
    # 每次都幂等地重写一遍，不管这次是不是为了加实例
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/v2node -f
        cat <<EOF > /etc/init.d/v2node
#!/sbin/openrc-run

name="v2node"
description="v2node"

: \${SVCNAME:=v2node}
if [ "\$SVCNAME" = "v2node" ]; then
    v2node_cfg="/etc/v2node/config.json"
else
    v2node_cfg="/etc/v2node/instances/\${SVCNAME#v2node.}/config.json"
fi

command="/usr/local/v2node/v2node"
command_args="server -c \${v2node_cfg}"
command_user="root"

pidfile="/run/\${SVCNAME}.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/v2node
        if [[ -z "$instance" ]]; then
            rc-update add v2node default
        else
            # openrc 靠脚本文件名认实例，做一个指到同一份脚本的 symlink
            ln -sf /etc/init.d/v2node "/etc/init.d/$(instance_init_name "$instance")"
            rc-update add "$(instance_init_name "$instance")" default
        fi
        echo -e "${green}v2node ${last_version}${plain} 安装完成，已设置开机自启"
    else
        if [[ -z "$instance" ]]; then
            rm /etc/systemd/system/v2node.service -f
            cat <<EOF > /etc/systemd/system/v2node.service
[Unit]
Description=v2node Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2node/
ExecStart=/usr/local/v2node/v2node server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        fi
        # 命名实例走 template unit（v2node@.service，%i 是实例名），一直存在、
        # 幂等重写，不影响默认实例已经在用的 v2node.service
        rm /etc/systemd/system/v2node@.service -f
        cat <<EOF > /etc/systemd/system/v2node@.service
[Unit]
Description=v2node Service (%i)
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2node/
ExecStart=/usr/local/v2node/v2node server -c /etc/v2node/instances/%i/config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        if [[ -z "$instance" ]]; then
            systemctl stop v2node
            systemctl enable v2node
        else
            systemctl enable "${svc}"
        fi
        echo -e "${green}v2node ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f "$cfg" ]]; then
        # 如果通过 CLI 传入了完整参数，则直接生成配置并跳过交互
        if [[ -n "$API_HOST_ARG" && -n "$NODE_ID_ARG" && -n "$API_KEY_ARG" ]]; then
            generate_v2node_config "$API_HOST_ARG" "$NODE_ID_ARG" "$API_KEY_ARG" "$NODE_TYPE_ARG" "$instance"
            echo -e "${green}已根据参数生成 ${cfg}${plain}"
            first_install=false
        else
            first_install=true
        fi
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$instance") start
        else
            systemctl start "${svc}"
        fi
        sleep 2
        check_status "$instance"
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node 重启成功${plain}"
        else
            echo -e "${red}v2node 可能启动失败，请使用 v2node log 查看日志信息${plain}"
        fi
        first_install=false
    fi


    curl -o /usr/bin/v2node -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/v2node.sh
    chmod +x /usr/bin/v2node

    cd $cur_dir
    rm -f install.sh
    echo "----------------------------------------------------------"
    echo -e "管理脚本使用方法: "
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
    echo "v2node log [name] [-f]         - 查看实例日志(默认最后1000行，-f 持续跟随)"
    echo "v2node config [name]           - 编辑实例配置并重启"
    echo "v2node generate                - 生成默认实例配置文件"
    echo "v2node update [version]        - 更新 v2node"
    echo "v2node install                 - 安装 v2node"
    echo "v2node uninstall               - 卸载 v2node（连同所有实例）"
    echo "v2node version                 - 查看 v2node 版本"
    echo "----------------------------------------------------------"
    # curl -fsS --max-time 10 "https://api.v-50.me/counter" || true

    if [[ $first_install == true ]]; then
        read -rp "检测到 ${cfg} 还不存在，是否现在生成？(y/n): " if_generate
        if [[ "$if_generate" =~ ^[Yy]$ ]]; then
            # 交互式收集参数，如果之前配置过其他实例，读上次用过的面板地址/
            # 密钥当默认值，直接回车即可沿用
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

            generate_v2node_config "$api_host" "$node_id" "$api_key" "$node_type" "$instance"
        else
            if [[ -z "$instance" ]]; then
                echo "${green}已跳过自动生成配置。如需后续生成，可执行: v2node generate${plain}"
            else
                echo "${green}已跳过自动生成配置。如需后续生成，可执行: v2node new ${instance}${plain}"
            fi
        fi
    fi
}

if [[ x"${release}" != x"alpine" ]]; then
    is_cmd_exist "systemctl"
    if [[ $? != 0 ]]; then
        echo -e "${red}systemctl 命令不存在，请使用较新版本的系统，例如 Ubuntu 18+、Debian 9+${plain}"
        exit 1
    fi
fi

parse_args "$@"
echo -e "${green}开始安装${plain}"
install_base
install_v2node "$VERSION_ARG"