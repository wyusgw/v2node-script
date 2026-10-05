#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error: ${plain} This script must be run as root!\n" && exit 1

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
    echo -e "${red}Cannot detect the system version, please contact the script author!${plain}\n" && exit 1
fi

########################
# Parse arguments
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
            --channel)
                CHANNEL_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [version] [--api-host URL] [--node-id ID] [--api-key KEY] [--node-type TYPE] [--instance NAME] [--channel stable|beta]"
                echo "--node-type is optional: when omitted the protocol is detected by the panel API (the v2node node type in the admin)"
                echo "To pin a protocol specific table, use one of: vmess / vless / trojan / shadowsocks / hysteria2 / tuic / anytls / mieru"
                echo "--instance is optional: when omitted the default instance is installed/updated (/etc/v2node/config.json, v2node.service)"
                echo "To run another fully independent v2node process on the same machine, give an instance name, e.g. --instance nodeB"
                echo "(creates /etc/v2node/nodeB.json and manages v2node@nodeB.service with systemctl, the default instance is not affected)"
                echo "--channel is optional: when omitted the previously chosen channel is reused (stable by default)"
                echo "stable = official release (releases/latest); beta = rolling build of the dev branch, may be unstable"
                exit 0 ;;
            --*)
                echo "Unknown argument: $1"; exit 1 ;;
            *)
                # Accept the first positional argument as the version
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

# Install channel: stable = latest release, beta = rolling build of the dev branch.
# Shared by all instances and remembered, so install/update without --channel reuses it.
CHANNEL_FILE="/etc/v2node/.channel"

get_channel() {
    if [[ -f "$CHANNEL_FILE" ]]; then
        cat "$CHANNEL_FILE"
    else
        echo "stable"
    fi
}

# An empty instance name means the default instance (/etc/v2node/config.json, v2node.service).
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

# Panel defaults come from the most recently modified existing instance config, so the key is not
# kept in a second plaintext file. Sets last_host / last_key (empty when there is no config).
load_panel_defaults() {
    last_host=""
    last_key=""
    local f
    f=$(ls -t /etc/v2node/config.json /etc/v2node/instances/*/config.json 2>/dev/null | head -1)
    [[ -n "$f" ]] || return 0
    last_host=$(sed -n 's/.*"ApiHost"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
    last_key=$(sed -n 's/.*"ApiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
}

# Show only the ends of a key in prompts
mask_key() {
    local k="$1"
    if (( ${#k} > 8 )); then
        echo "${k:0:3}***${k: -3}"
    else
        echo "***"
    fi
}

# Named instances live in /etc/v2node/instances/<name>/, the default instance keeps /etc/v2node/config.json.
instance_dir() {
    if [[ -z "$1" ]]; then
        echo "/etc/v2node"
    else
        echo "/etc/v2node/instances/$1"
    fi
}

# Alpine openrc has no systemd template units: one script plus per-instance symlinks, $SVCNAME gives the instance.
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
    echo -e "${red}Failed to detect the architecture, using the default: ${arch}${plain}"
fi

echo "System: ${release}  Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "This software does not support 32-bit systems (x86), please use a 64-bit system (x86_64). If the detection is wrong, please contact the author"
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
        echo -e "${red}Please use CentOS 7 or a newer system!${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Note: CentOS 7 cannot use the hysteria1/2 protocols!${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or a newer system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or a newer system!${plain}\n" && exit 1
    fi
fi

install_base() {
    # Check and install packages in batches to reduce system calls
    need_install_apt() {
        local packages=("$@")
        local missing=()
        
        # Batch check the installed packages
        local installed_list=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Installing missing packages: ${missing[*]}"
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_yum() {
        local packages=("$@")
        local missing=()
        
        # Batch check the installed packages
        local installed_list=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Installing missing packages: ${missing[*]}"
            yum install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_apk() {
        local packages=("$@")
        local missing=()
        
        # Batch check the installed packages
        local installed_list=$(apk info 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Installing missing packages: ${missing[*]}"
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
        fi
    }

    # Install all required packages at once
    if [[ x"${release}" == x"centos" ]]; then
        # Check and install epel-release
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo "Installing the EPEL repository..."
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
        echo "Updating the package database..."
        pacman -Sy --noconfirm >/dev/null 2>&1
        # --needed skips already installed packages
        echo "Installing the required packages..."
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates pv >/dev/null 2>&1
    fi
}

# 0: running, 1: not running, 2: not installed
# $1 (optional): instance name, defaults to the default instance
check_status() {
    local instance="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    # Judge by the existence of the config file: template unit instances usually do not show up in
    # systemctl list-unit-files, which made running named instances look "not installed".
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
    local options=("auto (protocol detected by the panel API, recommended)" "vmess" "vless" "trojan" "shadowsocks" "hysteria2" "tuic" "anytls" "mieru")
    local values=("v2node" "vmess" "vless" "trojan" "shadowsocks" "hysteria2" "tuic" "anytls" "mieru")
    echo "Select the node type:" >&2
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt" >&2
        i=$((i+1))
    done
    local choice
    while true; do
        read -rp "Enter the number [default: 1) auto]: " choice
        choice=${choice:-1}
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#values[@]} )); then
            echo "${values[$((choice-1))]}"
            return 0
        fi
        echo "Invalid input, please enter a number between 1 and ${#values[@]}" >&2
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
        echo -e "${green}v2node config file (${cfg}) generated, restarting the service${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$instance") restart
        else
            systemctl restart "${svc}"
        fi
        sleep 2
        check_status "$instance"
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node restarted successfully${plain}"
        else
            echo -e "${red}v2node may have failed to start, use v2node log${instance:+ $instance} to view the logs${plain}"
        fi
}

install_v2node() {
    local version_param="$1"
    local instance="$INSTANCE_ARG"
    local cfg=$(instance_config_path "$instance")
    local svc=$(instance_service_name "$instance")
    local had_binary=false
    [[ -f /usr/local/v2node/v2node ]] && had_binary=true
    # earlier versions kept a separate plaintext copy of the panel address and key
    rm -f /etc/v2node/.last_api_host /etc/v2node/.last_api_key

    local channel="${CHANNEL_ARG:-$(get_channel)}"
    if [[ "$channel" != "stable" && "$channel" != "beta" ]]; then
        echo -e "${red}Unknown install channel: ${channel}, it must be stable or beta${plain}"
        exit 1
    fi
    if [[ -n "$CHANNEL_ARG" ]]; then
        mkdir -p /etc/v2node
        echo "$channel" > "$CHANNEL_FILE"
    fi

    # When the main program is already installed, do not download it again: that would replace the
    # binary used by running instances. Binary and geo files are shared, config and service are per instance.
    if [[ -n "$instance" && -f /usr/local/v2node/v2node ]]; then
        echo -e "${green}v2node is already installed, skipping the download and only configuring instance [${instance}] service${plain}"
        last_version=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    else
    if [[ -e /usr/local/v2node/ ]]; then
        rm -rf /usr/local/v2node/
    fi

    mkdir /usr/local/v2node/ -p
    cd /usr/local/v2node/

    if [[ -z "$version_param" && "$channel" == "beta" ]]; then
        echo -e "${yellow}Current install channel: beta (rolling build of the dev branch, may be unstable)${plain}"
        last_version="beta"
        url="https://github.com/wyusgw/v2node/releases/download/beta/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "Download progress" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download the v2node beta, make sure your server can download files from GitHub, or the dev branch has no build artifact yet${plain}"
            exit 1
        fi
    elif  [[ -z "$version_param" ]] ; then
        last_version=$(curl -Ls "https://api.github.com/repos/wyusgw/v2node/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to detect the v2node version, the GitHub API limit may be exceeded. Try again later or specify the version manually${plain}"
            exit 1
        fi
        echo -e "${green}Latest version detected: ${last_version}. Installing...${plain}"
        url="https://github.com/wyusgw/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "Download progress" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download v2node, make sure your server can download files from GitHub${plain}"
            exit 1
        fi
    else
    last_version=$version_param
        url="https://github.com/wyusgw/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "Download progress" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download v2node $1, make sure this version exists${plain}"
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

    # The service/init definition is shared by all instances and rewritten idempotently every time.
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
            # openrc identifies the instance by the script file name, so symlink to the same script
            ln -sf /etc/init.d/v2node "/etc/init.d/$(instance_init_name "$instance")"
            rc-update add "$(instance_init_name "$instance")" default
        fi
        echo -e "${green}v2node ${last_version}${plain} installed, autostart enabled"
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
        # Named instances use the template unit (v2node@.service, %i is the instance name), rewritten idempotently
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
        echo -e "${green}v2node ${last_version}${plain} installed, autostart enabled"
    fi

    if [[ ! -f "$cfg" ]]; then
        # With complete CLI arguments, generate the config directly and skip the prompts
        if [[ -n "$API_HOST_ARG" && -n "$NODE_ID_ARG" && -n "$API_KEY_ARG" ]]; then
            generate_v2node_config "$API_HOST_ARG" "$NODE_ID_ARG" "$API_KEY_ARG" "$NODE_TYPE_ARG" "$instance"
            echo -e "${green}Generated from the arguments: ${cfg}${plain}"
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
            echo -e "${green}v2node restarted successfully${plain}"
        else
            echo -e "${red}v2node may have failed to start, use v2node log${instance:+ $instance} to view the logs${plain}"
        fi
        first_install=false
    fi


    curl -o /usr/bin/v2node -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/v2node.sh
    chmod +x /usr/bin/v2node

    cd $cur_dir
    rm -f install.sh
    echo "----------------------------------------------------------"
    echo -e "Management script usage: "
    echo "----------------------------------------------------------"
    echo "v2node                         - Show the management menu (more features)"
    echo "v2node list                    - List the instances and their status"
    echo "v2node new <name>              - Create an instance (collects the panel info interactively)"
    echo "v2node remove <name> [name...] - Remove an instance"
    echo "v2node rename <old> <new>      - Rename an instance"
    echo "v2node start [name]            - Start an instance (no name = default instance)"
    echo "v2node stop [name]             - Stop an instance"
    echo "v2node restart [name]          - Restart an instance"
    echo "v2node status [name]           - Show the instance status"
    echo "v2node enable [name]           - Enable autostart for an instance"
    echo "v2node disable [name]          - Disable autostart for an instance"
    echo "v2node log [name] [-f]         - Show the instance logs (last 1000 lines by default, -f to follow)"
    echo "v2node config [name]           - Edit the instance config and restart"
    echo "v2node generate                - Generate the default instance config file"
    echo "v2node update [version]        - Update v2node"
    echo "v2node install                 - Install v2node"
    echo "v2node uninstall               - Uninstall v2node (including all instances)"
    echo "v2node version                 - Show the v2node version"
    echo "----------------------------------------------------------"
    # curl -fsS --max-time 10 "https://api.v-50.me/counter" || true

    # When only named instances exist, an update has no default instance to configure,
    # so do not ask about generating the default config
    if [[ $first_install == true && $had_binary == true && -z "$instance" ]] && compgen -G "/etc/v2node/instances/*/config.json" >/dev/null; then
        first_install=false
    fi

    if [[ $first_install == true ]]; then
        read -rp "${cfg} does not exist yet, generate it now? (y/n): " if_generate
        if [[ "$if_generate" =~ ^[Yy]$ ]]; then
            # Collect the parameters interactively, reuse the last panel host/key as defaults
            local last_host="" last_key=""
            load_panel_defaults

            read -rp "Panel API URL [format: https://example.com/]${last_host:+ [default: $last_host]}: " api_host
            api_host=${api_host:-${last_host:-https://example.com/}}
            read -rp "Node ID: " node_id
            node_id=${node_id:-1}
            if [[ -n "$last_key" ]]; then
                read -rp "Node communication key [default: $(mask_key "$last_key")]: " api_key
                api_key=${api_key:-$last_key}
            else
                read -rp "Node communication key: " api_key
            fi
            node_type=$(choose_node_type)

            generate_v2node_config "$api_host" "$node_id" "$api_key" "$node_type" "$instance"
        else
            if [[ -z "$instance" ]]; then
                echo "${green}Skipped generating the config. To generate it later run: v2node generate${plain}"
            else
                echo "${green}Skipped generating the config. To generate it later run: v2node new ${instance}${plain}"
            fi
        fi
    fi
}

if [[ x"${release}" != x"alpine" ]]; then
    is_cmd_exist "systemctl"
    if [[ $? != 0 ]]; then
        echo -e "${red}The systemctl command does not exist, please use a newer system such as Ubuntu 18+ or Debian 9+${plain}"
        exit 1
    fi
fi

parse_args "$@"
echo -e "${green}Starting the installation${plain}"
install_base
install_v2node "$VERSION_ARG"