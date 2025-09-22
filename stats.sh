#!/bin/bash

# Script for reading real-time performance data for Linux
#
# Optimized for ASUS motherboards, but may work for other manufacturers if specific modules are loaded.
# For ASUS, the nct6798 module must be loaded.
# Compatible with AMD Radeon RX, NVIDIA GTX/RTX and Intel Arc graphics cards (although more information is available for AMD Radeon RX).
#
# Copyright (C) 2025 Felipe Miguel Nery Lunkes
# All rights reserved.

# Get CPU usage
function get_cpu_usage() {

read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_idle=$((idle + iowait))
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

sleep 0.1

read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

idle2=$((idle + iowait))
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
totald=$((total2 - prev_total))
idled=$((idle2 - prev_idle))

cpu_perc=$(( (1000 * (totald - idled) / totald + 5) / 10 ))

# Barra de 20 blocos
blocks=$(( cpu_perc * 20 / 100 ))
[ "$blocks" -lt 0 ] && blocks=0
[ "$blocks" -gt 20 ] && blocks=20

filled=$(printf "%0.s#" $(seq 1 $blocks))
empty=$(printf "%0.s " $(seq 1 $((20 - blocks))))
bar="$filled$empty"
bar="${GREEN}${bar}${NC}"

echo "$cpu_perc|$bar"
}

# Get CPU temperature
function get_cpu_temp() {

    awk -F':' '/Tctl|Core 0/ {print $2}' <<< "$sensors_out" | awk '{print $1}' | head -n1
}

# Get GPU temperature
function get_gpu_temp() {

if command -v nvidia-smi &> /dev/null; then
   nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -n1
else
   awk -F':' '/junction|edge/ {print $2}' <<< "$sensors_out" | awk '{print $1}' | head -n1
fi
}

function show_details() {

# Get CPU name
CPU_NAME=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//')

# Get GPU name
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
else
    GPU_NAME=$(lspci | awk -F': ' '/VGA compatible controller/ {print $2; exit}')
    GPU_NAME=$(echo "$GPU_NAME" | grep -o '\[Radeon RX[^]]*\]' | tr -d '[]')
fi

while :; do

sensors_out=$(sensors)

# Get memory usage and create load bar
read total used free <<< $(LC_ALL=C free -m | awk '/^Mem/ {print $2, $3, $4}')
total=${total:-0}; used=${used:-0}; free=${free:-0}
total_gb=$(awk -v t="$total" 'BEGIN{printf "%.1f", t/1024}')
used_gb=$(awk -v u="$used"  'BEGIN{printf "%.1f", u/1024}')
free_gb=$(awk -v f="$free"  'BEGIN{printf "%.1f", f/1024}')
perc=$(( total>0 ? used*100/total : 0 ))
blocks=$(( perc*20/100 ))
bar=$(printf "%-${blocks}s" "#" | tr ' ' '#')
bar=$(printf "%-20s" "$bar")

# Get fan information
gpu_fan1=$(awk '$1=="amdgpu-pci-0300"{chip="gpu"} chip=="gpu" && $1=="fan1:"{print $2; exit}' <<<"$sensors_out")
mobo_fan1=$(awk '$1=="nct6798-isa-0290"{chip="mobo"} chip=="mobo" && $1=="fan1:"{print $2; exit}' <<<"$sensors_out")

# Get CPU usage
cpu_data=$(get_cpu_usage)
cpu_perc="${cpu_data%%|*}"
cpu_bar="${cpu_data##*|}"

clear
echo -e "${CYAN}=== Real-time performance (every ${TIME}s) ===${NC}\n"

echo -e "${YELLOW}CPU${NC} - $CPU_NAME"
echo " > Temp (°C):    $(get_cpu_temp)"
echo -e " > Load:         [$cpu_bar] $cpu_perc%"

echo -e "${YELLOW}GPU${NC} - $GPU_NAME"
if [[ "$GPU_NAME" == Radeon* ]]; then
    # For AMD Radeon RX
    hot=$(awk -F':' '/junction/ {print $2}' <<<"$sensors_out" | awk '{print $1}')
    edge=$(awk -F':' '/edge/     {print $2}' <<<"$sensors_out" | awk '{print $1}')
    mem=$(awk -F':' '/mem/      {print $2}' <<<"$sensors_out" | awk '{print $1}')
    gpu_fan1=$(awk '$1=="amdgpu-pci-0300"{chip="gpu"} chip=="gpu" && $1=="fan1:"{print $2; exit}' <<<"$sensors_out")
    echo " > Hotspot (°C): $hot"
    echo " > Edge (°C):    $edge"
    echo " > Memory (°C):  $mem"
    echo " > Fan (RPM):    $gpu_fan1"
else
    # For NVIDIA or Intel Arc GPUs
    echo " > Temp (°C):    $(get_gpu_temp)"
fi

echo -e "${YELLOW}SSD${NC}"
echo " > NVME (°C):    $(awk -F':' '/Composite/ {print $2}' <<<"$sensors_out" | awk '{print $1}')"

echo -e "${YELLOW}Fans (RPM)${NC}"
echo " > CPU:          $(awk -F':' '/fan2/ {print $2}' <<<"$sensors_out" | awk '{print $1}')"
echo " > Chassis 1:    $(awk -F':' '/fan3/ {print $2}' <<<"$sensors_out" | awk '{print $1}')"
echo " > Chassis 2:    $mobo_fan1"

echo -e "${YELLOW}RAM Memory${NC}"
echo " > Total:        $total_gb GB"
echo " > Used:         $used_gb GB"
echo " > Free:         $free_gb GB"
echo -e " > Load:         [${GREEN}${bar}${NC}] $perc%"

echo -e "\n${CYAN}Press [Ctrl+C] to exit...${NC}"

sleep "$TIME"

done
}

# Show all sensors
function show_all() {

while :; do

sensors

sleep "$TIME"

done
}

RED="\033[1;31m";
GREEN="\033[1;32m";
CYAN="\033[1;36m";
YELLOW="\033[1;33m";
NC="\033[0m"

# Update interval
TIME=${1:-5}

case $2 in
    all) show_all; exit;;
    *)   show_details; exit;;
esac

