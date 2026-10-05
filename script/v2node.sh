#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

SCRIPT_VERSION="1.0.0"

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

instance_init_name() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "v2node.$1"
    fi
}

# Display name for logs and prompts: "v2node" for the default instance, "instance [name]" otherwise
instance_label() {
    if [[ -z "$1" ]]; then
        echo "v2node"
    else
        echo "instance [$1]"
    fi
}

# Name shown in the main menu entry "Manage instance [xxx]": the default instance shows as default
instance_display_name() {
    if [[ -z "$1" ]]; then
        echo "default"
    else
        echo "$1"
    fi
}

# The install channel file is shared with install.sh, each side reads it on its own
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
        echo "beta"
    else
        echo "stable"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [default $2]: " temp
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

# Only wait for Enter. Never call show_menu recursively: the outer loop redraws the menu,
# otherwise a long interactive session would keep deepening the bash call stack.
before_show_menu() {
    echo && echo -n -e "${yellow}Press Enter to return to the main menu: ${plain}" && read temp
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
        echo && echo -n -e "Enter a version (default: latest): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) $version
    if [[ $? == 0 ]]; then
        # Only the default instance is restarted by the update; named instances keep running the old
        # binary until restarted, so list them
        local named=() d
        if [[ -d /etc/v2node/instances ]]; then
            for d in /etc/v2node/instances/*/; do
                [[ -e "$d" ]] && named+=("$(basename "$d")")
            done
        fi
        if [[ -f /etc/v2node/config.json && ${#named[@]} -eq 0 ]]; then
            echo -e "${green}Update finished, v2node has been restarted, use v2node log to view the logs${plain}"
        elif [[ -f /etc/v2node/config.json ]]; then
            echo -e "${green}Update finished, the default instance has been restarted, use v2node log [name] to view the logs (no name = default instance)${plain}"
        else
            echo -e "${green}Update finished, use v2node log <name> to view the logs${plain}"
        fi
        if [[ ${#named[@]} -gt 0 ]]; then
            echo -e "${yellow}Named instances [${named[*]}] need v2node restart <name> each to use the new version${plain}"
        fi
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# $1: silent (non-empty = do not return to the main menu, used by the CLI)
switch_channel() {
    local silent="$1"
    local cur target target_label
    cur=$(get_channel)
    target="beta"
    target_label="beta"
    if [[ "$cur" == "beta" ]]; then
        target="stable"
        target_label="stable"
    fi
    echo -e "Current install channel: $(channel_label)"
    if [[ "$target" == "beta" ]]; then
        echo -e "${yellow}The beta is a rolling build of the dev branch and may be unstable, use it in test environments only${plain}"
    fi
    confirm "Switch to ${target_label}?" "n"
    if [[ $? != 0 ]]; then
        [[ -z "$silent" ]] && before_show_menu
        return 0
    fi
    mkdir -p /etc/v2node
    echo "$target" > "$CHANNEL_FILE"
    echo -e "${green}Switched to ${target_label}${plain}, the next install/update will use this channel"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        [[ -z "$silent" ]] && before_show_menu
        return 0
    fi
    confirm "Reinstall/update v2node with the new channel now" "y"
    if [[ $? == 0 ]]; then
        update 0 ""
    fi
    [[ -z "$silent" ]] && before_show_menu
}

# $1: instance name (empty = default instance)  $2: silent (non-empty = do not return to the main menu)
config() {
    local name="$1"
    local silent="$2"
    local cfg=$(instance_config_path "$name")
    if [[ ! -f "$cfg" ]]; then
        echo -e "${red}$(instance_label "$name") has no config file yet${plain}"
        [[ -n "$name" ]] && echo -e "${yellow}Run this first: v2node new ${name}${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    echo "The service will be restarted after the config is changed: $(instance_label "$name")"
    vi "$cfg"
    sleep 2
    restart "$name" 0
    check_status "$name"
    case $? in
        0)
            echo -e "$(instance_label "$name") status: ${green}running${plain}"
            ;;
        1)
            echo -e "$(instance_label "$name") is not running or the automatic restart failed, view the logs? [Y/n]" && echo
            read -e -rp "(default: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               log "$name" "" 0
            fi
            ;;
        2)
            echo -e "$(instance_label "$name") status: ${red}not installed${plain}"
    esac
    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

# Full uninstall: also stops and removes all named instances so no orphan service is left
uninstall() {
    confirm "Uninstall v2node? (all instances will be removed too)" "n"
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
    echo -e "Uninstalled. To remove this script, exit it and run ${green}rm /usr/bin/v2node -f${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# The lifecycle commands share one format: FUNC [instance] [silent]
# An empty instance means the default instance; a non-empty silent skips the interactive menu (CLI use).

start() {
    local name="$1"
    local silent="$2"
    check_status "$name"
    local st=$?
    if [[ $st == 2 ]]; then
        echo -e "${red}$(instance_label "$name") is not installed or configured yet${plain}"
    elif [[ $st == 0 ]]; then
        echo ""
        echo -e "${green}$(instance_label "$name") is already running, choose restart if you want to restart it${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service $(instance_init_name "$name") start
        else
            systemctl start "$(instance_service_name "$name")"
        fi
        sleep 2
        check_status "$name"
        if [[ $? == 0 ]]; then
            echo -e "${green}$(instance_label "$name") started, use v2node log${name:+ $name} to view the logs${plain}"
        else
            echo -e "${red}$(instance_label "$name") may have failed to start, check the logs later with v2node log${name:+ $name}${plain}"
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
        echo -e "${green}$(instance_label "$name") stopped${plain}"
    else
        echo -e "${red}$(instance_label "$name") failed to stop, it may have taken more than two seconds, check the logs later${plain}"
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
        echo -e "${green}$(instance_label "$name") restarted, use v2node log${name:+ $name} to view the logs${plain}"
    else
        echo -e "${red}$(instance_label "$name") may have failed to start, check the logs later with v2node log${name:+ $name}${plain}"
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
        echo -e "${green}$(instance_label "$name") autostart enabled${plain}"
    else
        echo -e "${red}$(instance_label "$name") failed to enable autostart${plain}"
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
        echo -e "${green}$(instance_label "$name") autostart disabled${plain}"
    else
        echo -e "${red}$(instance_label "$name") failed to disable autostart${plain}"
    fi

    if [[ -z "$silent" ]]; then
        before_show_menu
    fi
}

# $1: instance name  $2: follow (non-empty = -f, otherwise the last 1000 lines)  $3: silent
log() {
    local name="$1"
    local follow="$2"
    local silent="$3"
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}Log viewing is not supported on alpine yet${plain}"
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
        echo -e "${red}Failed to download the script, check that this machine can reach GitHub${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2node
        echo -e "${green}Script upgraded, please run it again${plain}" && exit 0
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
        # "systemctl status" also reads the journal tail, which is slow on hosts with large
        # journals and runs for every instance on each menu display; SubState needs no journal
        temp=$(systemctl show -p SubState "${svc}" 2>/dev/null | cut -d= -f2)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# $1 (optional): instance name, defaults to the default instance
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
        echo -e "${red}v2node is already installed, please do not install it again${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# $1: instance name (empty = default instance)  $2: silent (non-empty = do not return to the main menu)
check_install() {
    local instance="$1"
    local silent="$2"
    check_status "$instance"
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}$(instance_label "$instance") is not installed or configured yet${plain}"
        if [[ -z "$silent" ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# Only checks that the main program is installed, used by the global commands (update/version/list/uninstall)
check_binary_install() {
    local silent="$1"
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        echo ""
        echo -e "${red}Please install v2node first${plain}"
        if [[ -z "$silent" ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# List the default instance and all named instances with their status (v2node list)
list() {
    echo "Known instances:"
    if [[ -f /etc/v2node/config.json ]]; then
        check_status ""
        case $? in
            0) echo -e "  default  (v2node.service): ${green}running${plain}" ;;
            1) echo -e "  default  (v2node.service): ${yellow}not running${plain}" ;;
            *) echo -e "  default  (v2node.service): ${red}unknown${plain}" ;;
        esac
    fi
    local d name
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            name=$(basename "$d")
            check_status "$name"
            case $? in
                0) echo -e "  ${name}  (v2node@${name}.service): ${green}running${plain}" ;;
                1) echo -e "  ${name}  (v2node@${name}.service): ${yellow}not running${plain}" ;;
                *) echo -e "  ${name}  (v2node@${name}.service): ${red}unknown${plain}" ;;
            esac
        done
    fi
}

# Create a named instance (v2node new <name>): collect the panel info, then delegate to install.sh --instance
new() {
    local name="$1"
    local silent="$2"
    if [[ -z "$name" ]]; then
        read -rp "Enter an instance name (letters/digits, e.g. nodeB): " name
    fi
    if [[ -z "$name" || "$name" == "config" ]]; then
        echo -e "${red}The instance name cannot be empty${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi
    if [[ -f "$(instance_config_path "$name")" ]]; then
        echo -e "${red}Instance [${name}] already exists, to change its config use: v2node config ${name}${plain}"
        if [[ -z "$silent" ]]; then before_show_menu; fi
        return 1
    fi

    # Reuse the last used panel host/key as defaults, press Enter to keep them
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

    bash <(curl -Ls https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh) \
        --instance "$name" --api-host "$api_host" --node-id "$node_id" --api-key "$api_key" --node-type "$node_type"
    if [[ -z "$silent" ]]; then before_show_menu; fi
}

# Remove one or more named instances (v2node remove <name> [name...]), the default instance is untouched
remove() {
    if [[ $# == 0 ]]; then
        echo -e "${red}Please specify an instance name: v2node remove <name> [name...]${plain}"
        return 1
    fi
    local name
    for name in "$@"; do
        [[ -z "$name" ]] && continue
        confirm "Remove instance [${name}]? (the default instance and other instances are not affected)" "n"
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
        echo -e "${green}Instance [${name}] removed (the shared v2node program is not affected)${plain}"
    done
}

# Rename a named instance (v2node rename <old> <new>), the default instance cannot be renamed
rename() {
    local old="$1"
    local new_name="$2"
    if [[ -z "$old" || -z "$new_name" ]]; then
        echo -e "${red}Usage: v2node rename <old_name> <new_name>${plain}"
        return 1
    fi
    if [[ ! -f "$(instance_config_path "$old")" ]]; then
        echo -e "${red}Instance [${old}] does not exist, or it is the default instance (it cannot be renamed)${plain}"
        return 1
    fi
    if [[ -f "$(instance_config_path "$new_name")" ]]; then
        echo -e "${red}Instance [${new_name}] already exists, choose another name${plain}"
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

    echo -e "${green}Instance [${old}] renamed to [${new_name}]${plain}"
}

# Submenu for a single instance, the default instance cannot be renamed or removed (use full uninstall)
instance_submenu() {
    local name="$1"
    local max=8
    echo -e "
  ${green}Manage instance [$(instance_display_name "$name")]${plain}
————————————————
  ${green}1.${plain} Start
  ${green}2.${plain} Stop
  ${green}3.${plain} Restart
  ${green}4.${plain} Show status
  ${green}5.${plain} View logs
  ${green}6.${plain} Enable autostart
  ${green}7.${plain} Disable autostart
  ${green}8.${plain} Edit config"
    if [[ -n "$name" ]]; then
        max=10
        echo -e "  ${green}9.${plain} Rename this instance
  ${green}10.${plain} Remove this instance"
    fi
    echo -e "  ${green}0.${plain} Back to the main menu
 "
    read -rp "Enter your choice [0-${max}]: " iop
    case "$iop" in
        0) return ;;
        1) start "$name" 0 ;;
        2) stop "$name" 0 ;;
        3) restart "$name" 0 ;;
        4) status "$name" 0 ;;
        5) log "$name" "" 0 ;;
        6) enable "$name" 0 ;;
        7) disable "$name" 0 ;;
        8) config "$name" 0 ;;
        9)
            if [[ -n "$name" ]]; then
                read -rp "New name: " new_name
                rename "$name" "$new_name"
            else
                echo -e "${red}The default instance cannot be renamed${plain}"
            fi
            ;;
        10)
            if [[ -n "$name" ]]; then
                remove "$name"
            else
                echo -e "${red}The default instance cannot be removed, use 'Full uninstall'${plain}"
            fi
            ;;
        *) echo -e "${red}Please enter a valid number [0-${max}]${plain}" ;;
    esac
    before_show_menu
}

# Look up the latest version once; only called from the background refresh below,
# with short timeouts so an unreachable GitHub never holds up anything in the foreground.
fetch_latest_version() {
    local latest
    if [[ "$(get_channel)" == "beta" ]]; then
        latest=$(curl -Ls --connect-timeout 2 --max-time 4 "https://api.github.com/repos/wyusgw/v2node/git/refs/tags/beta" 2>/dev/null | grep '"sha":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | cut -c1-7)
        [[ -n "$latest" ]] && latest="beta-${latest}"
    else
        latest=$(curl -Ls --connect-timeout 2 --max-time 4 "https://api.github.com/repos/wyusgw/v2node/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    echo "$latest"
}

# The menu header calls this on every display, so it must never wait for the network:
# print the cached value and refresh it in the background when missing or older than 6 hours
# (the new value shows up the next time the menu is displayed).
get_latest_version() {
    local dir="/run"
    [[ -d "$dir" && -w "$dir" ]] || dir="/tmp"
    local cache="${dir}/.v2node_latest_$(get_channel)"
    if [[ -s "$cache" ]]; then
        cat "$cache"
    fi
    if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +360 2>/dev/null)" ]]; then
        (
            latest=$(fetch_latest_version)
            if [[ -n "$latest" ]]; then
                echo "$latest" > "${cache}.tmp" && mv -f "${cache}.tmp" "$cache"
            fi
        ) >/dev/null 2>&1 &
    fi
}

# Version line at the top of the main menu, checks the latest GitHub version live
show_version_header() {
    local installed=""
    if [[ -f /usr/local/v2node/v2node ]]; then
        installed=$(/usr/local/v2node/v2node version 2>/dev/null | awk '{print $2}')
    fi
    if [[ -n "$installed" ]]; then
        echo -e "  ${green}v2node management script v${SCRIPT_VERSION}${plain}  [v2node: ${installed}]  [channel: $(channel_label)]"
        local latest
        latest=$(get_latest_version)
        if [[ -n "$latest" && "$latest" != "$installed" ]]; then
            echo -e "  ${yellow}New version found: v2node ${latest}${plain}"
        fi
    else
        echo -e "  ${green}v2node management script v${SCRIPT_VERSION}${plain}  [v2node: not installed]  [channel: $(channel_label)]"
    fi
}

# Instance list at the bottom of the main menu: status, autostart and config path of each instance
show_instance_list() {
    echo ""
    echo "  Instances:"
    local status_text enable_text
    if [[ -f /etc/v2node/config.json ]]; then
        check_status ""
        case $? in
            0) status_text="${green}running${plain}" ;;
            1) status_text="${yellow}not running${plain}" ;;
            *) status_text="${red}not installed${plain}" ;;
        esac
        check_enabled ""
        if [[ $? == 0 ]]; then enable_text="${green}yes${plain}"; else enable_text="${red}no${plain}"; fi
        printf "    %-12s [%b] [autostart: %b]  %s\n" "default" "$status_text" "$enable_text" "/etc/v2node/config.json"
    fi

    local d name
    if [[ -d /etc/v2node/instances ]]; then
        for d in /etc/v2node/instances/*/; do
            [[ -e "$d" ]] || continue
            name=$(basename "$d")
            check_status "$name"
            case $? in
                0) status_text="${green}running${plain}" ;;
                1) status_text="${yellow}not running${plain}" ;;
                *) status_text="${red}not installed${plain}" ;;
            esac
            check_enabled "$name"
            if [[ $? == 0 ]]; then enable_text="${green}yes${plain}"; else enable_text="${red}no${plain}"; fi
            printf "    %-12s [%b] [autostart: %b]  %s\n" "$name" "$status_text" "$enable_text" "$(instance_config_path "$name")"
        done
    fi
}

# Install and update share one entry: install when missing, update when installed
install_or_update() {
    # check_status "" only looks at the default instance, so it reports "not installed" whenever
    # the default instance has no config (e.g. only named instances exist) and would wrongly run a
    # fresh install, which wipes the shared binary directory
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        install
    else
        update
    fi
}

show_v2node_version() {
    echo -n "v2node version: "
    /usr/local/v2node/v2node version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
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
        echo -e "${green}V2node config generated, restarting the service${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node restart
        else
            systemctl restart v2node
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node restarted successfully${plain}"
        else
            echo -e "${red}v2node may have failed to start, use v2node log to view the logs${plain}"
        fi
}


generate_config_file() {
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

    generate_v2node_config "$api_host" "$node_id" "$api_key" "$node_type"
}

# Open the firewall ports
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
    echo -e "${green}Firewall ports opened!${plain}"
}

show_usage() {
    echo "v2node management script usage: "
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
    echo "v2node channel [stable|beta]   - Show/switch the install channel (no argument = show the current channel)"
    echo "v2node update_shell            - Update the management script"
    echo "----------------------------------------------------------"
}

show_menu() {
    show_version_header
    echo -e "
  ${green}0.${plain} Exit
————————————————
  ${green}1.${plain} Install/update v2node
  ${green}2.${plain} Full uninstall of v2node
————————————————
  ${green}3.${plain} Update the management script
  ${green}4.${plain} Switch the install channel [current: $(channel_label)]
  ${green}5.${plain} Add a v2node instance
————————————————"

    # Each existing instance gets its own numbered menu line starting from 6
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
    local i num_i=6
    for i in "${menu_instances[@]}"; do
        echo -e "  ${green}${num_i}.${plain} Manage instance [$(instance_display_name "$i")]"
        num_i=$((num_i + 1))
    done
    echo " "
    show_instance_list
    local max=$((6 + ${#menu_instances[@]} - 1))
    echo && read -rp "Enter your choice [0-${max}] or [instance name]: " num

    case "${num}" in
        0|"") echo -e "${red}Enter your choice [0-${max}]${plain}" && exit ;;
        1) install_or_update ;;
        2) check_binary_install && uninstall ;;
        3) update_shell ;;
        4) switch_channel ;;
        5) new "" ;;
        *)
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 6 && num < 6 + ${#menu_instances[@]} )); then
                local picked="${menu_instances[$((num - 6))]}"
                check_install "$picked" && instance_submenu "$picked"
            elif [[ "$num" == "default" ]] || [[ -f "$(instance_config_path "$num")" ]]; then
                local picked=""
                [[ "$num" != "default" ]] && picked="$num"
                check_install "$picked" && instance_submenu "$picked"
            else
                echo -e "${red}Please enter a valid number [0-${max}], or the name of an existing instance${plain}"
                before_show_menu
            fi
            ;;
    esac
}

if [[ x"${release}" != x"alpine" ]]; then
    is_cmd_exist "systemctl"
    if [[ $? != 0 ]]; then
        echo -e "${red}The systemctl command does not exist, please use a newer system such as Ubuntu 18+ or Debian 9+${plain}"
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
            for log_arg in "$2" "$3"; do
                if [[ "$log_arg" == "-f" ]]; then
                    log_follow="1"
                elif [[ -n "$log_arg" ]]; then
                    log_name="$log_arg"
                fi
            done
            check_install "$log_name" 0 && log "$log_name" "$log_follow" 0
            ;;
        "config") check_install "$2" 0 && config "$2" 0 ;;
        "update") check_binary_install 0 && update 0 $2 ;;
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
                echo "Current install channel: $(channel_label)"
            elif [[ "$2" == "stable" || "$2" == "beta" ]]; then
                mkdir -p /etc/v2node
                echo "$2" > "$CHANNEL_FILE"
                echo -e "${green}Switched to $(channel_label)${plain}, the next install/update will use this channel, run v2node update to apply it now"
            else
                echo -e "${red}Unknown channel: $2, it must be stable or beta${plain}"
            fi
            ;;
        *) show_usage
    esac
else
    # Interactive mode redraws the main menu from this outer loop; show_menu, before_show_menu and
    # instance_submenu never call each other recursively, so the call stack does not grow with use.
    while true; do
        show_menu
    done
fi
