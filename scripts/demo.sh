#!/bin/bash
# ROBOTERM Demo Script — Run this to showcase features
# Usage: source scripts/demo.sh

# Must be sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Usage: source scripts/demo.sh"
    exit 1
fi

# Colors
O='\033[38;2;255;59;0m'
G='\033[38;2;0;255;136m'
C='\033[38;2;0;221;255m'
B='\033[1m'
D='\033[2m'
R='\033[0m'
Y='\033[38;2;255;184;0m'

clear

echo -e "${O}${B}"
echo "  ____   ___  ____   ___ _____ _____ ____  __  __ "
echo " |  _ \\ / _ \\| __ ) / _ \\_   _| ____|  _ \\|  \\/  |"
echo " | |_) | | | |  _ \\| | | || | |  _| | |_) | |\\/| |"
echo " |  _ <| |_| | |_) | |_| || | | |___|  _ <| |  | |"
echo " |_| \\_\\\\___/|____/ \\___/ |_| |_____|_| \\_\\_|  |_|"
echo -e "${R}"
echo -e "${D}  The first ROS2-native agentic terminal for Apple Silicon${R}"
echo -e "${D}  Built by RobotFlow Labs • Pure Swift • SwiftTerm Engine${R}"
echo ""

sleep 2

echo -e "${O}━━━ WHAT MAKES ROBOTERM DIFFERENT ━━━${R}"
echo ""
echo -e "  ${G}●${R} ${B}Agent Launcher Bar${R} — One-click Claude Code & Codex"
echo -e "  ${G}●${R} ${B}60+ ROS2 Commands${R} — Menus, right-click, agent bar"
echo -e "  ${G}●${R} ${B}31 CLI Commands${R}   — rt init, rt nodes, rt topics, rt build..."
echo -e "  ${G}●${R} ${B}Native SSH${R}        — Direct PTY, sidebar panel, one-click connect"
echo -e "  ${G}●${R} ${B}Hardware Detection${R} — IOKit USB hotplug (ZED, RealSense, LiDAR)"
echo -e "  ${G}●${R} ${B}AppleScript${R}       — Full Cocoa scripting support"
echo -e "  ${G}●${R} ${B}Status Bar${R}        — Live CPU/MEM/git/ROS2/SSH info"
echo ""

sleep 2

echo -e "${O}━━━ DEMO: rt doctor ━━━${R}"
echo -e "${D}  (System diagnostics — warnings expected without ROS2/Docker installed)${R}"
echo ""
sleep 1

# Source tools if not already loaded
if ! type rt &>/dev/null; then
    _demo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$_demo_dir/roboterm-tools.sh" 2>/dev/null
    unset _demo_dir
fi

if ! type rt &>/dev/null; then
    echo -e "${Y}⚠  Could not auto-source rt tools.${R}"
    echo -e "${Y}   Run: source $(cd "$(dirname "$0")" && pwd)/roboterm-tools.sh${R}"
    echo ""
else
    rt init 2>/dev/null
    rt doctor
fi

echo ""
sleep 2

echo -e "${O}━━━ COMPETITIVE POSITIONING ━━━${R}"
echo ""
echo -e "  ${D}Foxglove raised \$15M on visualization alone.${R}"
echo -e "  ${D}We own the bigger market: developer iteration.${R}"
echo ""
echo -e "  ${C}Foxglove${R}  = analysis (postmortem, dashboards)"
echo -e "  ${O}ROBOTERM${R} = iteration (local dev, debugging, speed)"
echo -e "  ${G}Together${R} = complementary, not competing"
echo ""

sleep 2

echo -e "${O}━━━ MARKET ━━━${R}"
echo ""
echo -e "  50,000 ROS2 developers globally"
echo -e "  70% on macOS → 35,000 potential users"
echo -e "  Apple Silicon accelerating → M1/M2/M3/M4"
echo -e "  TAM: \$2.1M/year (freemium @ \$10/mo)"
echo ""

echo -e "${O}━━━ LIVE: Docker ROS2 Stack ━━━${R}"
echo ""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    _running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${G}●${R} Docker: ${_running} containers running"
    docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read -r name status; do
        echo -e "    ${D}${name}  ${status}${R}"
    done
    echo ""

    # Check if ROS2 bridge is running
    if docker exec anima_ros2_gazebo bash -c "source /opt/ros/jazzy/setup.bash && ros2 topic list" &>/dev/null; then
        _topics=$(docker exec anima_ros2_gazebo bash -c "source /opt/ros/jazzy/setup.bash && ros2 topic list 2>/dev/null" | wc -l | tr -d ' ')
        _nodes=$(docker exec anima_ros2_gazebo bash -c "source /opt/ros/jazzy/setup.bash && ros2 node list 2>/dev/null" | wc -l | tr -d ' ')
        echo -e "  ${G}●${R} ROS2 Jazzy: ${_nodes} nodes, ${_topics} topics"
        echo -e "  ${D}  Sensors: camera (×3), lidar, IMU, odometry${R}"
        echo -e "  ${D}  Web viewer: http://localhost:8080${R}"
        echo ""

        # Publish a velocity command
        echo -e "  ${C}▶${R} Publishing cmd_vel (robot moves!)..."
        docker exec anima_ros2_gazebo bash -c "source /opt/ros/jazzy/setup.bash && ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist '{linear: {x: 0.3}, angular: {z: 0.2}}'" &>/dev/null
        echo -e "  ${G}●${R} Robot commanded: linear=0.3 angular=0.2"
    else
        echo -e "  ${Y}●${R} ROS2 bridge not active in Docker"
    fi
    unset _running _topics _nodes
else
    echo -e "  ${Y}●${R} Docker not running"
fi
echo ""

sleep 2

echo -e "${O}━━━ NEXT: ANIMA Full Stack ━━━${R}"
echo ""
echo -e "  ${D}10 perception modules shipping by end of March:${R}"
echo -e "  ${G}●${R} AZOTH  — Object Detection"
echo -e "  ${G}●${R} CHRONOS — Temporal Tracking"
echo -e "  ${G}●${R} MONAD  — Scene Reasoning"
echo -e "  ${G}●${R} LOCI   — Spatial Mapping"
echo -e "  ${G}●${R} OSIRIS — System Diagnostics"
echo -e "  ${G}●${R} PETRA  — Motion Planning"
echo ""
echo -e "  ${C}All controlled from this terminal.${R}"
echo ""

echo -e "${G}${B}  Try it: type 'rt' for all commands${R}"
echo ""
