#!/bin/bash
# ROBOTERM Shell Tools — source this in your .bashrc/.zshrc
# Usage: source /path/to/roboterm-tools.sh
# Or add to ~/.bashrc: source /Applications/ROBOTERM.app/Contents/Resources/roboterm-tools.sh

# ============================================================
# ROBOTERM — ROS2 Developer Tools
# ============================================================

export ROBOTERM_VERSION="0.1.0"

# Colors
_RT_ORANGE='\033[38;2;255;59;0m'
_RT_GREEN='\033[38;2;0;255;136m'
_RT_CYAN='\033[38;2;0;221;255m'
_RT_YELLOW='\033[38;2;255;184;0m'
_RT_RED='\033[38;2;255;51;51m'
_RT_DIM='\033[2m'
_RT_BOLD='\033[1m'
_RT_RESET='\033[0m'

_rt_header() {
    echo -e "${_RT_ORANGE}${_RT_BOLD}━━━ ROBOTERM: $1 ━━━${_RT_RESET}"
}

_rt_ok() { echo -e "  ${_RT_GREEN}●${_RT_RESET} $1"; }
_rt_warn() { echo -e "  ${_RT_YELLOW}●${_RT_RESET} $1"; }
_rt_err() { echo -e "  ${_RT_RED}●${_RT_RESET} $1"; }
_rt_info() { echo -e "  ${_RT_CYAN}●${_RT_RESET} $1"; }
_rt_dim() { echo -e "  ${_RT_DIM}$1${_RT_RESET}"; }

# ============================================================
# rt init — Auto-detect and source ROS2 workspace
# ============================================================
rt-init() {
    _rt_header "Workspace Init"

    # Walk up to find colcon workspace
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/install/setup.bash" ]; then
            source "$dir/install/setup.bash"
            _rt_ok "Sourced: $dir/install/setup.bash"
            if [ -n "$ROS_DISTRO" ]; then
                _rt_ok "ROS2 Distro: $ROS_DISTRO"
            fi
            if [ -n "$ROS_DOMAIN_ID" ]; then
                _rt_ok "Domain ID: $ROS_DOMAIN_ID"
            else
                _rt_warn "Domain ID: 0 (default)"
            fi
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # Try system ROS2
    for distro in rolling jazzy iron humble; do
        if [ -f "/opt/homebrew/opt/ros/$distro/setup.bash" ]; then
            source "/opt/homebrew/opt/ros/$distro/setup.bash"
            _rt_ok "Sourced system ROS2: $distro"
            return 0
        fi
        if [ -f "/opt/ros/$distro/setup.bash" ]; then
            source "/opt/ros/$distro/setup.bash"
            _rt_ok "Sourced system ROS2: $distro"
            return 0
        fi
    done

    _rt_err "No ROS2 workspace found. Create one with: mkdir -p ~/ros2_ws/src && cd ~/ros2_ws && colcon build"
    return 1
}

# ============================================================
# rt nodes — Live node dashboard
# ============================================================
rt-nodes() {
    _rt_header "Node Dashboard"
    echo ""
    if ! command -v ros2 &>/dev/null; then
        _rt_err "ROS2 not sourced. Run: rt-init"
        return 1
    fi

    local nodes=$(ros2 node list 2>/dev/null)
    if [ -z "$nodes" ]; then
        _rt_warn "No nodes running"
        return 0
    fi

    echo -e "${_RT_DIM}  NAME                              STATUS${_RT_RESET}"
    echo -e "${_RT_DIM}  ──────────────────────────────────────────${_RT_RESET}"
    while IFS= read -r node; do
        _rt_ok "$node"
    done <<< "$nodes"
    echo ""
    local count=$(echo "$nodes" | wc -l | tr -d ' ')
    _rt_info "Total: $count nodes"
}

# ============================================================
# rt topics — Topic monitor with Hz
# ============================================================
rt-topics() {
    _rt_header "Topic Monitor"
    echo ""
    if ! command -v ros2 &>/dev/null; then
        _rt_err "ROS2 not sourced. Run: rt-init"
        return 1
    fi

    echo -e "${_RT_DIM}  TOPIC                              TYPE                           PUBS  SUBS${_RT_RESET}"
    echo -e "${_RT_DIM}  ────────────────────────────────────────────────────────────────────────────────${_RT_RESET}"
    ros2 topic list -v 2>/dev/null | while IFS= read -r line; do
        if [[ "$line" == /* ]]; then
            # Topic line
            echo -e "  ${_RT_GREEN}●${_RT_RESET} ${_RT_BOLD}$line${_RT_RESET}"
        elif [[ "$line" == *"Published"* ]] || [[ "$line" == *"Subscribed"* ]]; then
            echo -e "    ${_RT_DIM}$line${_RT_RESET}"
        fi
    done
    echo ""
    local count=$(ros2 topic list 2>/dev/null | wc -l | tr -d ' ')
    _rt_info "Total: $count topics"
}

# ============================================================
# rt services — Service list
# ============================================================
rt-services() {
    _rt_header "Services"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    ros2 service list -t 2>/dev/null | while IFS= read -r line; do
        local svc=$(echo "$line" | awk '{print $1}')
        local typ=$(echo "$line" | awk '{print $2}')
        echo -e "  ${_RT_CYAN}●${_RT_RESET} ${_RT_BOLD}$svc${_RT_RESET}  ${_RT_DIM}$typ${_RT_RESET}"
    done
}

# ============================================================
# rt params — Parameter browser
# ============================================================
rt-params() {
    _rt_header "Parameters"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local node="${1:-}"
    if [ -z "$node" ]; then
        ros2 param list 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" == /* ]]; then
                echo -e "\n  ${_RT_ORANGE}${_RT_BOLD}$line${_RT_RESET}"
            else
                echo -e "    ${_RT_DIM}$line${_RT_RESET}"
            fi
        done
    else
        ros2 param list "$node" 2>/dev/null | while IFS= read -r param; do
            local val=$(ros2 param get "$node" "$param" 2>/dev/null | head -1)
            echo -e "  ${_RT_CYAN}$param${_RT_RESET} = ${_RT_GREEN}$val${_RT_RESET}"
        done
    fi
}

# ============================================================
# rt doctor — System diagnostics
# ============================================================
rt-doctor() {
    _rt_header "System Diagnostics"
    echo ""

    # Check ROS2
    if command -v ros2 &>/dev/null; then
        _rt_ok "ROS2 CLI: $(which ros2)"
        if [ -n "$ROS_DISTRO" ]; then
            _rt_ok "Distro: $ROS_DISTRO"
        else
            _rt_warn "ROS_DISTRO not set"
        fi
    else
        _rt_err "ROS2 CLI not found"
    fi

    # Check Domain ID
    _rt_info "Domain ID: ${ROS_DOMAIN_ID:-0}"

    # Check DDS
    if [ -n "$RMW_IMPLEMENTATION" ]; then
        _rt_ok "DDS: $RMW_IMPLEMENTATION"
    else
        _rt_info "DDS: default (CycloneDDS)"
    fi

    # Check colcon
    if command -v colcon &>/dev/null; then
        _rt_ok "colcon: $(which colcon)"
    else
        _rt_warn "colcon not found"
    fi

    # Check Docker
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            _rt_ok "Docker: running"
        else
            _rt_warn "Docker: installed but not running"
        fi
    else
        _rt_dim "Docker: not installed"
    fi

    # Check sensors
    echo ""
    _rt_header "Hardware"
    if ioreg -p IOUSB -l 2>/dev/null | grep -q "ZED"; then
        _rt_ok "ZED Camera: connected"
    fi
    if ioreg -p IOUSB -l 2>/dev/null | grep -q "RealSense"; then
        _rt_ok "RealSense: connected"
    fi
    ls /dev/tty.usb* 2>/dev/null | while read dev; do
        _rt_info "Serial: $dev"
    done

    # Network
    echo ""
    _rt_header "Network Hosts"
    if [ -f ~/.config/roboterm/hosts.json ]; then
        python3 -c "
import json
with open('$HOME/.config/roboterm/hosts.json') as f:
    hosts = json.load(f)
for h in hosts:
    print(f'  {h[\"name\"]} ({h[\"host\"]})')
" 2>/dev/null
    fi
}

# ============================================================
# rt tf — Transform tree
# ============================================================
rt-tf() {
    _rt_header "Transform Tree"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local cmd="${1:-tree}"
    case "$cmd" in
        tree|frames)
            ros2 run tf2_tools view_frames 2>/dev/null
            _rt_ok "Generated: frames.pdf"
            ;;
        echo)
            shift
            ros2 run tf2_ros tf2_echo "$@" 2>/dev/null
            ;;
        monitor)
            ros2 run tf2_ros tf2_monitor 2>/dev/null
            ;;
        *)
            echo "Usage: rt-tf [tree|echo <src> <tgt>|monitor]"
            ;;
    esac
}

# ============================================================
# rt build — Smart colcon build
# ============================================================
rt-build() {
    _rt_header "Build"
    echo ""

    if ! command -v colcon &>/dev/null; then
        _rt_err "colcon not found"
        return 1
    fi

    local start_time=$(date +%s)

    if [ -n "$1" ]; then
        _rt_info "Building package: $1"
        colcon build --symlink-install --packages-select "$@"
    else
        _rt_info "Building all packages..."
        colcon build --symlink-install
    fi

    local status=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    if [ $status -eq 0 ]; then
        _rt_ok "Build succeeded in ${duration}s"
        # Auto-source after build
        if [ -f install/setup.bash ]; then
            source install/setup.bash
            _rt_ok "Sourced install/setup.bash"
        fi
    else
        _rt_err "Build failed after ${duration}s"
    fi
    return $status
}

# ============================================================
# rt bag — Bag file management
# ============================================================
rt-bag() {
    _rt_header "Bag Tools"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local cmd="${1:-list}"
    case "$cmd" in
        list|ls)
            find . -name "*.db3" -o -name "*.mcap" 2>/dev/null | while read f; do
                local size=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                _rt_info "$f ($size)"
            done
            ;;
        info)
            shift
            ros2 bag info "$@" 2>/dev/null
            ;;
        record)
            shift
            if [ -z "$1" ]; then
                _rt_info "Recording all topics..."
                ros2 bag record -a
            else
                _rt_info "Recording: $*"
                ros2 bag record "$@"
            fi
            ;;
        play)
            shift
            ros2 bag play "$@" 2>/dev/null
            ;;
        *)
            echo "Usage: rt-bag [list|info <bag>|record [topics...]|play <bag>]"
            ;;
    esac
}

# ============================================================
# rt hz — Topic frequency monitor
# ============================================================
rt-hz() {
    if [ -z "$1" ]; then
        echo "Usage: rt-hz <topic>"
        return 1
    fi
    ros2 topic hz "$@"
}

# ============================================================
# rt echo — Pretty topic echo
# ============================================================
rt-echo() {
    if [ -z "$1" ]; then
        echo "Usage: rt-echo <topic>"
        return 1
    fi
    ros2 topic echo "$@" | python3 -c "
import sys, json
try:
    for line in sys.stdin:
        print(line, end='')
except:
    pass
" 2>/dev/null || ros2 topic echo "$@"
}

# ============================================================
# rt launch — Enhanced launch
# ============================================================
rt-launch() {
    _rt_header "Launch"
    if [ -z "$1" ]; then
        echo "Usage: rt-launch <package> <launch_file> [args...]"
        return 1
    fi
    echo ""
    _rt_info "Launching: $*"
    echo ""
    ros2 launch "$@"
}

# ============================================================
# rt dds — DDS diagnostics
# ============================================================
rt-dds() {
    _rt_header "DDS Configuration"
    echo ""
    _rt_info "Domain ID: ${ROS_DOMAIN_ID:-0}"
    _rt_info "RMW: ${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp (default)}"
    if [ -n "$CYCLONEDDS_URI" ]; then
        _rt_info "CycloneDDS Config: $CYCLONEDDS_URI"
    fi
    echo ""
    _rt_info "Running ros2 daemon status..."
    ros2 daemon status 2>/dev/null
}

# ============================================================
# rt docker — Docker helpers for ROS2
# ============================================================
rt-docker() {
    local cmd="${1:-ps}"
    case "$cmd" in
        ps)     docker compose ps 2>/dev/null || docker ps ;;
        up)     docker compose up -d ;;
        down)   docker compose down ;;
        logs)   docker compose logs -f --tail=50 ;;
        shell)
            local container="${2:-}"
            if [ -z "$container" ]; then
                container=$(docker ps --format "{{.Names}}" | head -1)
            fi
            _rt_info "Entering: $container"
            docker exec -it "$container" bash
            ;;
        *)
            echo "Usage: rt-docker [ps|up|down|logs|shell [container]]"
            ;;
    esac
}

# ============================================================
# rt lifecycle — Node lifecycle management
# ============================================================
rt-lifecycle() {
    _rt_header "Lifecycle Nodes"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local cmd="${1:-list}"
    case "$cmd" in
        list)
            ros2 lifecycle nodes 2>/dev/null | while IFS= read -r node; do
                local state=$(ros2 lifecycle get "$node" 2>/dev/null | tail -1)
                case "$state" in
                    *active*)       _rt_ok "$node — ${state}" ;;
                    *inactive*)     _rt_warn "$node — ${state}" ;;
                    *unconfigured*) _rt_info "$node — ${state}" ;;
                    *)              _rt_dim "$node — ${state}" ;;
                esac
            done
            ;;
        get)    shift; ros2 lifecycle get "$@" ;;
        set)    shift; ros2 lifecycle set "$@" ;;
        *)      echo "Usage: rt lifecycle [list|get <node>|set <node> <state>]" ;;
    esac
}

# ============================================================
# rt sensor — Sensor monitoring
# ============================================================
rt-sensor() {
    _rt_header "Sensor Monitor"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local cmd="${1:-list}"
    case "$cmd" in
        list)
            echo -e "${_RT_DIM}  Searching for sensor topics...${_RT_RESET}"
            echo ""
            # Camera topics
            ros2 topic list 2>/dev/null | grep -i "camera\|image\|rgb\|depth" | while read t; do
                local hz=$(timeout 3 ros2 topic hz "$t" --window 3 2>/dev/null | head -1 | awk '{print $NF}')
                _rt_ok "CAM  $t  ${hz:-?}Hz"
            done
            # LiDAR topics
            ros2 topic list 2>/dev/null | grep -i "scan\|lidar\|points\|cloud" | while read t; do
                _rt_ok "LDR  $t"
            done
            # IMU topics
            ros2 topic list 2>/dev/null | grep -i "imu\|accel\|gyro\|mag" | while read t; do
                _rt_ok "IMU  $t"
            done
            # GPS topics
            ros2 topic list 2>/dev/null | grep -i "gps\|fix\|nav_sat" | while read t; do
                _rt_ok "GPS  $t"
            done
            ;;
        watch)
            shift
            if [ -z "$1" ]; then echo "Usage: rt sensor watch <topic>"; return 1; fi
            ros2 topic echo "$@"
            ;;
        hz)
            shift
            if [ -z "$1" ]; then echo "Usage: rt sensor hz <topic>"; return 1; fi
            ros2 topic hz "$@"
            ;;
        bw)
            shift
            if [ -z "$1" ]; then echo "Usage: rt sensor bw <topic>"; return 1; fi
            ros2 topic bw "$@"
            ;;
        *)
            echo "Usage: rt sensor [list|watch <topic>|hz <topic>|bw <topic>]"
            ;;
    esac
}

# ============================================================
# rt ssh — SSH to configured robots
# ============================================================
rt-ssh() {
    _rt_header "SSH Robot Access"
    echo ""

    if [ -z "$1" ]; then
        # List configured hosts
        if [ -f ~/.config/roboterm/hosts.json ]; then
            python3 -c "
import json
with open('$HOME/.config/roboterm/hosts.json') as f:
    hosts = json.load(f)
for i, h in enumerate(hosts):
    print(f'  [{i+1}] {h[\"name\"]:20s} {h[\"host\"]:20s} ({h[\"type\"]})')
" 2>/dev/null
            echo ""
            echo -e "${_RT_DIM}  Usage: rt ssh <name_or_number>${_RT_RESET}"
        else
            _rt_warn "No hosts configured. Create ~/.config/roboterm/hosts.json"
        fi
        return 0
    fi

    # Connect by name or number
    local target="$1"
    local host=$(python3 -c "
import json, sys
with open('$HOME/.config/roboterm/hosts.json') as f:
    hosts = json.load(f)
t = '$target'
if t.isdigit():
    idx = int(t) - 1
    if 0 <= idx < len(hosts):
        print(hosts[idx]['host'])
else:
    for h in hosts:
        if h['name'].lower() == t.lower():
            print(h['host'])
            break
" 2>/dev/null)

    if [ -n "$host" ]; then
        _rt_info "Connecting to: $host"
        ssh "$host"
    else
        _rt_err "Host '$target' not found"
    fi
}

# ============================================================
# rt watch — Watch multiple topics at once
# ============================================================
rt-watch() {
    _rt_header "Topic Watch"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    if [ -z "$1" ]; then
        echo "Usage: rt watch <topic1> [topic2] ..."
        echo "       rt watch --all (watch all topics hz)"
        return 1
    fi

    if [ "$1" = "--all" ]; then
        # Show all topics with their hz
        while true; do
            clear
            _rt_header "All Topics (Live)"
            echo ""
            echo -e "${_RT_DIM}  TOPIC                                    HZ${_RT_RESET}"
            echo -e "${_RT_DIM}  ─────────────────────────────────────────────${_RT_RESET}"
            ros2 topic list 2>/dev/null | while read t; do
                printf "  %-40s" "$t"
                timeout 2 ros2 topic hz "$t" --window 2 2>/dev/null | head -1 | awk '{printf "%.1f Hz\n", $NF}' || echo "?"
            done
            sleep 5
        done
    else
        # Watch specific topics
        for topic in "$@"; do
            echo -e "${_RT_GREEN}●${_RT_RESET} Watching: $topic"
            ros2 topic echo "$topic" --once 2>/dev/null &
        done
        wait
    fi
}

# ============================================================
# rt kill — Kill a ROS2 node
# ============================================================
rt-kill() {
    if [ -z "$1" ]; then
        echo "Usage: rt kill <node_name>"
        return 1
    fi
    _rt_header "Kill Node"
    _rt_warn "Killing: $1"
    # Try lifecycle transition first
    ros2 lifecycle set "$1" shutdown 2>/dev/null || \
    # Fallback: find PID and kill
    pkill -f "$1" 2>/dev/null
}

# ============================================================
# rt graph — ASCII node graph
# ============================================================
rt-graph() {
    _rt_header "Node Graph"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    echo -e "${_RT_DIM}  Mapping node connections...${_RT_RESET}"
    echo ""

    ros2 node list 2>/dev/null | while IFS= read -r node; do
        echo -e "  ${_RT_ORANGE}${_RT_BOLD}$node${_RT_RESET}"

        # Publishers
        ros2 node info "$node" 2>/dev/null | grep -A50 "Publishers:" | grep -B0 "Subscribers:\|Service Servers:\|$" | grep "/" | head -5 | while read topic; do
            echo -e "    ${_RT_GREEN}→ PUB${_RT_RESET} $topic"
        done

        # Subscribers
        ros2 node info "$node" 2>/dev/null | grep -A50 "Subscribers:" | grep -B0 "Service Servers:\|Service Clients:\|$" | grep "/" | head -5 | while read topic; do
            echo -e "    ${_RT_CYAN}← SUB${_RT_RESET} $topic"
        done

        echo ""
    done
}

# ============================================================
# rt status — One-line system status
# ============================================================
rt-status() {
    local ros2_status="OFF"
    local nodes=0
    local topics=0
    local docker_status="OFF"

    if command -v ros2 &>/dev/null; then
        ros2_status="${ROS_DISTRO:-?}"
        nodes=$(ros2 node list 2>/dev/null | wc -l | tr -d ' ')
        topics=$(ros2 topic list 2>/dev/null | wc -l | tr -d ' ')
    fi

    if docker info &>/dev/null 2>&1; then
        docker_status="ON"
    fi

    local usb_count=$(ioreg -p IOUSB -l 2>/dev/null | grep -c "USB Product Name" || echo "0")

    echo -e "${_RT_ORANGE}ROBOTERM${_RT_RESET} | ROS2:${_RT_GREEN}${ros2_status}${_RT_RESET} | Nodes:${nodes} | Topics:${topics} | Docker:${_RT_GREEN}${docker_status}${_RT_RESET} | USB:${usb_count} | Domain:${ROS_DOMAIN_ID:-0}"
}

# ============================================================
# rt info — Show ROBOTERM version and environment
# ============================================================
rt-info() {
    _rt_header "Environment"
    echo ""
    _rt_info "ROBOTERM v${ROBOTERM_VERSION}"
    _rt_info "Shell: $SHELL"
    _rt_info "Term: ${TERM_PROGRAM:-unknown}"
    _rt_info "Arch: $(uname -m)"
    _rt_info "macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    _rt_info "Chip: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
    echo ""
    if [ -n "$ROS_DISTRO" ]; then
        _rt_ok "ROS2: $ROS_DISTRO"
    else
        _rt_dim "ROS2: not sourced"
    fi
    _rt_info "Domain: ${ROS_DOMAIN_ID:-0}"
    _rt_info "DDS: ${RMW_IMPLEMENTATION:-default}"
    echo ""
    _rt_info "Config: ~/.config/roboterm/"
    _rt_info "Hosts: ~/.config/roboterm/hosts.json"
    _rt_info "Theme: ~/.config/ghostty/config"
}

# ============================================================
# rt profile — Environment profiles (dev/sim/hardware)
# ============================================================
rt-profile() {
    local profiles_dir="$HOME/.config/roboterm/profiles"

    local cmd="${1:-list}"
    case "$cmd" in
        list)
            _rt_header "Profiles"
            echo ""
            if [ -d "$profiles_dir" ]; then
                for f in "$profiles_dir"/*.env; do
                    [ -f "$f" ] || continue
                    local name=$(basename "$f" .env)
                    _rt_info "$name"
                done
            else
                _rt_dim "No profiles. Create: rt profile create <name>"
            fi
            ;;
        create)
            shift
            local name="${1:-dev}"
            mkdir -p "$profiles_dir"
            cat > "$profiles_dir/$name.env" << 'ENVEOF'
# ROBOTERM Profile
# Source this to configure your ROS2 environment
# Usage: rt profile load <name>

# ROS2
# export ROS_DISTRO=jazzy
# export ROS_DOMAIN_ID=0

# DDS
# export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
# export CYCLONEDDS_URI=file:///path/to/config.xml

# Workspace
# source ~/ros2_ws/install/setup.bash

# Custom
# export ROBOT_NAME=spectra-x1
ENVEOF
            _rt_ok "Created profile: $profiles_dir/$name.env"
            _rt_info "Edit it, then load with: rt profile load $name"
            ;;
        load)
            shift
            local name="${1:-dev}"
            local file="$profiles_dir/$name.env"
            if [ -f "$file" ]; then
                source "$file"
                _rt_ok "Loaded profile: $name"
            else
                _rt_err "Profile not found: $name"
                _rt_dim "Available: $(ls "$profiles_dir"/*.env 2>/dev/null | xargs -I{} basename {} .env | tr '\n' ' ')"
            fi
            ;;
        save)
            shift
            local name="${1:-current}"
            mkdir -p "$profiles_dir"
            {
                echo "# ROBOTERM Profile — saved $(date)"
                [ -n "$ROS_DISTRO" ] && echo "export ROS_DISTRO=$ROS_DISTRO"
                [ -n "$ROS_DOMAIN_ID" ] && echo "export ROS_DOMAIN_ID=$ROS_DOMAIN_ID"
                [ -n "$RMW_IMPLEMENTATION" ] && echo "export RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION"
                [ -n "$AMENT_PREFIX_PATH" ] && echo "export AMENT_PREFIX_PATH=$AMENT_PREFIX_PATH"
                [ -n "$CYCLONEDDS_URI" ] && echo "export CYCLONEDDS_URI=$CYCLONEDDS_URI"
            } > "$profiles_dir/$name.env"
            _rt_ok "Saved current env as profile: $name"
            ;;
        *)
            echo "Usage: rt profile [list|create <name>|load <name>|save <name>]"
            ;;
    esac
}

# ============================================================
# rt export — Export data to Foxglove/CSV
# ============================================================
rt-export() {
    _rt_header "Export"
    echo ""
    if ! command -v ros2 &>/dev/null; then _rt_err "ROS2 not sourced"; return 1; fi

    local cmd="${1:-help}"
    case "$cmd" in
        bag2csv)
            shift
            if [ -z "$1" ]; then echo "Usage: rt export bag2csv <bag_dir>"; return 1; fi
            _rt_info "Exporting bag to CSV..."
            ros2 bag convert -i "$1" -o "${1%.db3}.csv" -s csv 2>/dev/null || \
            _rt_warn "Direct CSV export not available. Use: rt export bag2mcap first, then open in Foxglove."
            ;;
        bag2mcap)
            shift
            if [ -z "$1" ]; then echo "Usage: rt export bag2mcap <bag_dir>"; return 1; fi
            _rt_info "Converting to MCAP format (Foxglove-compatible)..."
            ros2 bag convert -i "$1" -o "${1}_mcap" -s mcap 2>/dev/null && \
            _rt_ok "Exported: ${1}_mcap" || \
            _rt_err "MCAP conversion failed. Install: pip install mcap"
            ;;
        foxglove)
            shift
            local bag="${1:-}"
            if [ -z "$bag" ]; then
                _rt_info "Opening Foxglove Studio..."
                open "https://app.foxglove.dev" 2>/dev/null || echo "Visit: https://app.foxglove.dev"
            else
                _rt_info "Open this bag in Foxglove: $bag"
                _rt_dim "Drag the .mcap file into Foxglove Studio"
            fi
            ;;
        *)
            echo "Usage: rt export [bag2csv <bag>|bag2mcap <bag>|foxglove [bag]]"
            ;;
    esac
}

# ============================================================
# rt alias — Custom command shortcuts
# ============================================================
rt-alias() {
    local aliases_file="$HOME/.config/roboterm/aliases.sh"

    local cmd="${1:-list}"
    case "$cmd" in
        list)
            _rt_header "Aliases"
            echo ""
            if [ -f "$aliases_file" ]; then
                cat "$aliases_file" | grep -v "^#" | grep -v "^$" | while read line; do
                    _rt_info "$line"
                done
            else
                _rt_dim "No aliases. Create: rt alias add <name> <command>"
            fi
            ;;
        add)
            shift
            local name="$1"; shift
            local command="$*"
            if [ -z "$name" ] || [ -z "$command" ]; then
                echo "Usage: rt alias add <name> <command>"
                return 1
            fi
            mkdir -p "$(dirname "$aliases_file")"
            echo "alias rt-$name='$command'" >> "$aliases_file"
            eval "alias rt-$name='$command'"
            _rt_ok "Added alias: rt-$name → $command"
            ;;
        *)
            echo "Usage: rt alias [list|add <name> <command>]"
            ;;
    esac

    # Source aliases if file exists
    [ -f "$aliases_file" ] && source "$aliases_file"
}

# ============================================================
# rt disk — Disk usage for robotics data
# ============================================================
rt-disk() {
    _rt_header "Disk Usage"
    echo ""

    local cmd="${1:-.}"
    case "$cmd" in
        bags)
            _rt_info "Bag files:"
            find . -name "*.db3" -o -name "*.mcap" 2>/dev/null | while read f; do
                local size=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                echo -e "    ${_RT_YELLOW}$size${_RT_RESET}  $f"
            done | sort -rh
            echo ""
            local total=$(find . -name "*.db3" -o -name "*.mcap" -exec du -c {} + 2>/dev/null | tail -1 | awk '{print $1}')
            _rt_info "Total bags: $(echo "$total" | numfmt --to=iec 2>/dev/null || echo "${total}K")"
            ;;
        large)
            _rt_info "Largest files (top 20):"
            find "${2:-.}" -type f -size +100M 2>/dev/null | head -20 | while read f; do
                local size=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                echo -e "    ${_RT_YELLOW}$size${_RT_RESET}  $f"
            done | sort -rh
            ;;
        clean)
            _rt_info "Cleaning build artifacts..."
            if [ -d build ]; then
                local sz=$(du -sh build 2>/dev/null | awk '{print $1}')
                rm -rf build
                _rt_ok "Removed build/ ($sz)"
            fi
            if [ -d install ]; then
                local sz=$(du -sh install 2>/dev/null | awk '{print $1}')
                rm -rf install log
                _rt_ok "Removed install/ + log/ ($sz)"
            fi
            ;;
        *)
            _rt_info "Current directory: $(du -sh "${cmd}" 2>/dev/null | awk '{print $1}')"
            echo ""
            du -sh "${cmd}"/*/ 2>/dev/null | sort -rh | head -15 | while read line; do
                echo -e "    ${_RT_DIM}$line${_RT_RESET}"
            done
            echo ""
            echo "Usage: rt disk [bags|large [dir]|clean|<path>]"
            ;;
    esac
}

# ============================================================
# rt log — View and search ROS2 logs
# ============================================================
rt-log() {
    _rt_header "ROS2 Logs"
    echo ""

    local log_dir="${ROS_LOG_DIR:-$HOME/.ros/log}"

    local cmd="${1:-latest}"
    case "$cmd" in
        latest)
            local latest=$(ls -t "$log_dir"/*.log 2>/dev/null | head -1)
            if [ -n "$latest" ]; then
                _rt_info "Showing: $latest"
                tail -50 "$latest"
            else
                _rt_warn "No logs found in $log_dir"
            fi
            ;;
        follow|tail)
            local latest=$(ls -t "$log_dir"/*.log 2>/dev/null | head -1)
            if [ -n "$latest" ]; then
                _rt_info "Following: $latest"
                tail -f "$latest"
            fi
            ;;
        search)
            shift
            if [ -z "$1" ]; then echo "Usage: rt log search <pattern>"; return 1; fi
            _rt_info "Searching logs for: $1"
            grep -rn --color=always "$1" "$log_dir" 2>/dev/null | head -50
            ;;
        clean)
            local sz=$(du -sh "$log_dir" 2>/dev/null | awk '{print $1}')
            rm -rf "$log_dir"/*
            _rt_ok "Cleaned ROS2 logs ($sz)"
            ;;
        *)
            echo "Usage: rt log [latest|follow|search <pattern>|clean]"
            ;;
    esac
}

# ============================================================
# rt dupes — Find duplicate files by size+hash
# ============================================================
rt-dupes() {
    _rt_header "Duplicate Finder"
    echo ""

    local dir="${1:-.}"
    local min_size="${2:-10M}"

    _rt_info "Scanning: $dir (files > $min_size)"
    echo ""

    # Find files by size, then hash duplicates
    find "$dir" -type f -size +${min_size} 2>/dev/null | while read f; do
        du -h "$f" 2>/dev/null
    done | sort -rh | awk '{print $2}' | while read f; do
        md5 -q "$f" 2>/dev/null | tr -d '\n'
        echo "  $f"
    done | sort | uniq -D -w 32 | while read line; do
        local hash="${line:0:32}"
        local file="${line:34}"
        local size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
        echo -e "  ${_RT_YELLOW}$size${_RT_RESET}  ${_RT_DIM}$hash${_RT_RESET}  $file"
    done

    echo ""
    _rt_info "Usage: rt dupes [directory] [min_size]"
    _rt_info "Example: rt dupes ~/datasets 100M"
}

# ============================================================
# rt — Main entry point / help
# ============================================================
rt() {
    local cmd="${1:-help}"
    case "$cmd" in
        status)     shift; rt-status "$@" ;;
        info)       shift; rt-info "$@" ;;
        init)       shift; rt-init "$@" ;;
        nodes)      shift; rt-nodes "$@" ;;
        topics)     shift; rt-topics "$@" ;;
        services)   shift; rt-services "$@" ;;
        params)     shift; rt-params "$@" ;;
        doctor)     shift; rt-doctor "$@" ;;
        tf)         shift; rt-tf "$@" ;;
        build)      shift; rt-build "$@" ;;
        bag)        shift; rt-bag "$@" ;;
        hz)         shift; rt-hz "$@" ;;
        echo)       shift; rt-echo "$@" ;;
        launch)     shift; rt-launch "$@" ;;
        dds)        shift; rt-dds "$@" ;;
        docker)     shift; rt-docker "$@" ;;
        lifecycle)  shift; rt-lifecycle "$@" ;;
        sensor)     shift; rt-sensor "$@" ;;
        ssh)        shift; rt-ssh "$@" ;;
        watch)      shift; rt-watch "$@" ;;
        kill)       shift; rt-kill "$@" ;;
        graph)      shift; rt-graph "$@" ;;
        profile)    shift; rt-profile "$@" ;;
        export)     shift; rt-export "$@" ;;
        alias)      shift; rt-alias "$@" ;;
        disk)       shift; rt-disk "$@" ;;
        log)        shift; rt-log "$@" ;;
        dupes)      shift; rt-dupes "$@" ;;
        help|*)
            echo -e "${_RT_ORANGE}${_RT_BOLD}"
            echo "  ____   ___  ____   ___ _____ _____ ____  __  __ "
            echo " |  _ \\ / _ \\| __ ) / _ \\_   _| ____|  _ \\|  \\/  |"
            echo " | |_) | | | |  _ \\| | | || | |  _| | |_) | |\\/| |"
            echo " |  _ <| |_| | |_) | |_| || | | |___|  _ <| |  | |"
            echo " |_| \\_\\\\___/|____/ \\___/ |_| |_____|_| \\_\\_|  |_|"
            echo -e "${_RT_RESET}"
            echo -e "${_RT_DIM}  The Terminal for Robotics Developers v$ROBOTERM_VERSION${_RT_RESET}"
            echo ""
            echo -e "  ${_RT_ORANGE}rt init${_RT_RESET}        Auto-detect & source ROS2 workspace"
            echo -e "  ${_RT_ORANGE}rt nodes${_RT_RESET}       Live node dashboard"
            echo -e "  ${_RT_ORANGE}rt topics${_RT_RESET}      Topic monitor with types"
            echo -e "  ${_RT_ORANGE}rt services${_RT_RESET}    Service list with types"
            echo -e "  ${_RT_ORANGE}rt params${_RT_RESET}      Parameter browser [node]"
            echo -e "  ${_RT_ORANGE}rt doctor${_RT_RESET}      System diagnostics"
            echo -e "  ${_RT_ORANGE}rt tf${_RT_RESET}          Transform tree [tree|echo|monitor]"
            echo -e "  ${_RT_ORANGE}rt build${_RT_RESET}       Smart colcon build [package]"
            echo -e "  ${_RT_ORANGE}rt bag${_RT_RESET}         Bag management [list|info|record|play]"
            echo -e "  ${_RT_ORANGE}rt hz${_RT_RESET}          Topic frequency <topic>"
            echo -e "  ${_RT_ORANGE}rt echo${_RT_RESET}        Pretty topic echo <topic>"
            echo -e "  ${_RT_ORANGE}rt launch${_RT_RESET}      Enhanced ros2 launch"
            echo -e "  ${_RT_ORANGE}rt dds${_RT_RESET}         DDS configuration & diagnostics"
            echo -e "  ${_RT_ORANGE}rt docker${_RT_RESET}      Docker helpers [ps|up|down|logs|shell]"
            echo -e "  ${_RT_ORANGE}rt lifecycle${_RT_RESET}  Node lifecycle [list|get|set]"
            echo -e "  ${_RT_ORANGE}rt sensor${_RT_RESET}     Sensor monitor [list|watch|hz|bw]"
            echo -e "  ${_RT_ORANGE}rt ssh${_RT_RESET}        SSH to robot [name|number]"
            echo -e "  ${_RT_ORANGE}rt watch${_RT_RESET}      Watch topics [topic...|--all]"
            echo -e "  ${_RT_ORANGE}rt kill${_RT_RESET}       Kill a ROS2 node"
            echo -e "  ${_RT_ORANGE}rt graph${_RT_RESET}      ASCII node connection graph"
            echo -e "  ${_RT_ORANGE}rt profile${_RT_RESET}    Environment profiles [list|create|load|save]"
            echo -e "  ${_RT_ORANGE}rt export${_RT_RESET}     Export to Foxglove [bag2csv|bag2mcap|foxglove]"
            echo -e "  ${_RT_ORANGE}rt alias${_RT_RESET}      Custom command shortcuts [list|add]"
            echo -e "  ${_RT_ORANGE}rt disk${_RT_RESET}       Disk usage [bags|large|clean]"
            echo -e "  ${_RT_ORANGE}rt log${_RT_RESET}        ROS2 logs [latest|follow|search|clean]"
            echo -e "  ${_RT_ORANGE}rt dupes${_RT_RESET}      Find duplicate files [dir] [min_size]"
            echo ""
            ;;
    esac
}

# Auto-complete
complete -W "init nodes topics services params doctor tf build bag hz echo launch dds docker lifecycle sensor ssh watch kill graph status info profile export alias disk log dupes help" rt

echo -e "${_RT_DIM}ROBOTERM tools loaded. Type ${_RT_ORANGE}rt${_RT_RESET}${_RT_DIM} for help.${_RT_RESET}"
