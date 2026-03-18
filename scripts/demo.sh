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
echo -e "  ${G}●${R} ${B}30 CLI Commands${R}   — rt init, rt nodes, rt topics, rt build..."
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
    source "$(dirname "$0")/roboterm-tools.sh" 2>/dev/null
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

echo -e "${G}${B}  Try it: type 'rt' for all commands${R}"
echo ""
