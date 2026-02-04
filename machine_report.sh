#!/bin/bash
# TR-100 Machine Report
# Copyright © 2024, U.S. Graphics, LLC. BSD-3-Clause License.

# Global variables
MIN_NAME_LEN=5
MAX_NAME_LEN=13

MIN_DATA_LEN=20
MAX_DATA_LEN=32

BORDERS_AND_PADDING=7

# Basic configuration, change as needed
report_title="UNITED STATES GRAPHICS COMPANY"
last_login_ip_present=0
zfs_present=0
zfs_filesystem="zroot/ROOT/os"

# Utilities
max_length() {
    local max_len=0
    local len

    for str in "$@"; do
        len=${#str}
        if (( len > max_len )); then
            max_len=$len
        fi
    done

    if [ $max_len -lt $MAX_DATA_LEN ]; then
        printf '%s' "$max_len"
    else
        printf '%s' "$MAX_DATA_LEN"
    fi
}

# All data strings must go here
set_current_len() {
    CURRENT_LEN=$(max_length                                     \
        "$report_title"                                          \
        "$os_name"                                               \
        "$os_kernel"                                             \
        "$net_hostname"                                          \
        "$net_machine_ip"                                        \
        "$net_client_ip"                                         \
        "$net_current_user"                                      \
        "$cpu_model"                                             \
        "$cpu_cores_per_socket vCPU(s) / $cpu_sockets Socket(s)" \
        "$cpu_hypervisor"                                        \
        "$cpu_freq GHz"                                          \
        "$cpu_1min_bar_graph"                                    \
        "$cpu_5min_bar_graph"                                    \
        "$cpu_15min_bar_graph"                                   \
        "$zfs_used_gb/$zfs_available_gb GB [$disk_percent%]"     \
        "$disk_bar_graph"                                        \
        "$zfs_health"                                            \
        "$root_used_gb/$root_total_gb GB [$disk_percent%]"       \
        "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"   \
        "${mem_bar_graph}"                                       \
        "$last_login_time"                                       \
        "$last_login_ip"                                         \
        "$last_login_ip"                                         \
        "$sys_uptime"                                            \
    )
}

PRINT_HEADER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))

    local top="┌"
    local bottom="├"
    for (( i = 0; i < length - 2; i++ )); do
        top+="┬"
        bottom+="┴"
    done
    top+="┐"
    bottom+="┤"

    printf '%s\n' "$top"
    printf '%s\n' "$bottom"
}

PRINT_CENTERED_DATA() {
    local max_len=$((CURRENT_LEN+MAX_NAME_LEN-BORDERS_AND_PADDING))
    local text="$1"
    local total_width=$((max_len + 12))

    local text_len=${#text}
    local padding_left=$(( (total_width - text_len) / 2 ))
    local padding_right=$(( total_width - text_len - padding_left ))

    printf "│%${padding_left}s%s%${padding_right}s│\n" "" "$text" ""
}

PRINT_DIVIDER() {
    # either "top" or "bottom", no argument means middle divider
    local side="$1"
    case "$side" in
        "top")
            local left_symbol="├"
            local middle_symbol="┬"
            local right_symbol="┤"
            ;;
        "bottom")
            local left_symbol="└"
            local middle_symbol="┴"
            local right_symbol="┘"
            ;;
        *)
            local left_symbol="├"
            local middle_symbol="┼"
            local right_symbol="┤"
    esac

    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local divider="$left_symbol"
    for (( i = 0; i < length - 3; i++ )); do
        divider+="─"
        if [ "$i" -eq 14 ]; then
            divider+="$middle_symbol"
        fi
    done
    divider+="$right_symbol"
    printf '%s\n' "$divider"
}

PRINT_DATA() {
    local name="$1"
    local data="$2"
    local max_data_len=$CURRENT_LEN

    # Pad name
    local name_len=${#name}
    if (( name_len < MIN_NAME_LEN )); then
        name=$(printf "%-${MIN_NAME_LEN}s" "$name")
    elif (( name_len > MAX_NAME_LEN )); then
        name=$(echo "$name" | cut -c 1-$((MAX_NAME_LEN-3)))...
    else
        name=$(printf "%-${MAX_NAME_LEN}s" "$name")
    fi

    # Truncate or pad data
    local data_len=${#data}
    if (( data_len >= MAX_DATA_LEN || data_len == MAX_DATA_LEN-1 )); then
        data=$(echo "$data" | cut -c 1-$((MAX_DATA_LEN-3-2)))...
    else
        data=$(printf "%-${max_data_len}s" "$data")
    fi

    printf "│ %-${MAX_NAME_LEN}s │ %s │\n" "$name" "$data"
}

PRINT_FOOTER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local footer="└"
    for (( i = 0; i < length - 3; i++ )); do
        footer+="─"
        if [ "$i" -eq 14 ]; then
            footer+="┴"
        fi
    done
    footer+="┘"
    printf '%s\n' "$footer"
}

bar_graph() {
    local percent
    local num_blocks
    local width=$CURRENT_LEN
    local graph=""
    local used=$1
    local total=$2

    if (( total == 0 )); then
        percent=0
    else
        percent=$(awk -v used="$used" -v total="$total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
    fi

    num_blocks=$(awk -v percent="$percent" -v width="$width" 'BEGIN { printf "%d", (percent / 100) * width }')

    for (( i = 0; i < num_blocks; i++ )); do
        graph+="█"
    done
    for (( i = num_blocks; i < width; i++ )); do
        graph+="░"
    done
    printf "%s" "${graph}"
}

get_ip_addr() {
    # Initialize variables
    ipv4_address=""
    ipv6_address=""

    if command -v ifconfig &> /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS ifconfig format: interface names don't have colons
            ipv4_address=$(ifconfig | awk '
                /^[a-z]/ {iface=$1}
                iface != "lo0" && iface != "lo0:" && iface !~ /^docker/ && iface !~ /^utun/ && /inet / && !/127\.0\.0\.1/ && !found_ipv4 {found_ipv4=1; print $2}')

            if [ -z "$ipv4_address" ]; then
                ipv6_address=$(ifconfig | awk '
                    /^[a-z]/ {iface=$1}
                    iface != "lo0" && iface != "lo0:" && iface !~ /^docker/ && iface !~ /^utun/ && /inet6 / && !/::1/ && !/fe80:/ && !found_ipv6 {found_ipv6=1; print $2}')
            fi
        else
            # Linux ifconfig format: interface names have colons
            ipv4_address=$(ifconfig | awk '
                /^[a-z]/ {iface=$1}
                iface != "lo:" && iface !~ /^docker/ && /inet / && !found_ipv4 {found_ipv4=1; print $2}')

            if [ -z "$ipv4_address" ]; then
                ipv6_address=$(ifconfig | awk '
                    /^[a-z]/ {iface=$1}
                    iface != "lo:" && iface !~ /^docker/ && /inet6 / && !found_ipv6 {found_ipv6=1; print $2}')
            fi
        fi
    elif command -v ip &> /dev/null; then
        # Linux: use ip command as fallback
        ipv4_address=$(ip -o -4 addr show | awk '
            $2 != "lo" && $2 !~ /^docker/ {split($4, a, "/"); if (!found_ipv4++) print a[1]}')

        if [ -z "$ipv4_address" ]; then
            ipv6_address=$(ip -o -6 addr show | awk '
                $2 != "lo" && $2 !~ /^docker/ {split($4, a, "/"); if (!found_ipv6++) print a[1]}')
        fi
    fi

    # macOS fallback: try ipconfig getifaddr
    if [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ] && [[ "$OSTYPE" == "darwin"* ]]; then
        for iface in en0 en1 en2 en3; do
            ipv4_address=$(ipconfig getifaddr "$iface" 2>/dev/null)
            if [ -n "$ipv4_address" ]; then
                break
            fi
        done
    fi

    # If neither IPv4 nor IPv6 address is available, assign "No IP found"
    if [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ]; then
        ip_address="No IP found"
    else
        # Prioritize IPv4 if available, otherwise use IPv6
        ip_address="${ipv4_address:-$ipv6_address}"
    fi

    printf '%s' "$ip_address"
}

# Operating System Information
if [[ "$OSTYPE" == "darwin"* ]]; then
    os_name="macOS $(sw_vers -productVersion) $(sw_vers -buildVersion)"
else
    # shellcheck source=/dev/null
    source /etc/os-release
    os_name="${ID^} ${VERSION} ${VERSION_CODENAME^}"
fi
os_kernel=$({ uname; uname -r; } | tr '\n' ' ')

# Network Information
net_current_user=$(whoami)
if [[ "$OSTYPE" == "darwin"* ]]; then
    net_hostname=$(scutil --get LocalHostName 2>/dev/null || hostname -f 2>/dev/null || uname -n)
else
    if command -v hostname &>/dev/null; then
        net_hostname=$(hostname -f 2>/dev/null || uname -n)
    else
        net_hostname=$(grep -w "$(uname -n)" /etc/hosts | awk '{print $2}' | head -n 1)
    fi
fi
if [ -z "$net_hostname" ]; then net_hostname="Not Defined"; fi

net_machine_ip=$(get_ip_addr)
# Get client IP: prefer SSH env vars, then parse who am i
if [ -n "$SSH_CLIENT" ]; then
    net_client_ip=$(echo "$SSH_CLIENT" | awk '{print $1}')
elif [ -n "$SSH_CONNECTION" ]; then
    net_client_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
else
    # Parse who am i - look for field in parentheses containing IP or hostname
    net_client_ip=$(who am i 2>/dev/null | grep -oE '\([^)]+\)' | tr -d '()')
fi
# Validate: must look like IP or hostname, not a time (HH:MM)
if [ -z "$net_client_ip" ] || [[ "$net_client_ip" =~ ^[0-9]+:[0-9]+$ ]]; then
    net_client_ip="Not connected"
fi

# DNS servers
if [[ "$OSTYPE" == "darwin"* ]]; then
    net_dns_ip=($(scutil --dns 2>/dev/null | grep 'nameserver\[' | awk '{print $3}' | sort -u))
else
    net_dns_ip=($(grep '^nameserver [0-9.]' /etc/resolv.conf | awk '{print $2}'))
fi

# CPU Information
if [[ "$OSTYPE" == "darwin"* ]]; then
    cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null | awk '{print $1, $2, $3, $4}')"
    if [ -z "$cpu_model" ]; then
        # Apple Silicon doesn't have brand_string, use chip info
        cpu_model="$(sysctl -n machdep.cpu.brand 2>/dev/null)"
        if [ -z "$cpu_model" ]; then
            cpu_model="Apple $(uname -m)"
        fi
    fi

    # Check if running in a VM
    if sysctl -n machdep.cpu.features 2>/dev/null | grep -q "VMM"; then
        cpu_hypervisor="Virtual Machine"
    elif system_profiler SPHardwareDataType 2>/dev/null | grep -q "Virtual"; then
        cpu_hypervisor="Virtual Machine"
    else
        cpu_hypervisor="Bare Metal"
    fi

    cpu_cores="$(sysctl -n hw.ncpu)"
    cpu_cores_per_socket="$(sysctl -n hw.physicalcpu 2>/dev/null || echo "$cpu_cores")"
    cpu_sockets="1"

    # Get CPU frequency in GHz
    cpu_freq_hz="$(sysctl -n hw.cpufrequency 2>/dev/null)"
    if [ -n "$cpu_freq_hz" ] && [ "$cpu_freq_hz" -gt 0 ]; then
        cpu_freq=$(awk -v freq="$cpu_freq_hz" 'BEGIN { printf "%.2f", freq / 1000000000 }')
    else
        # Apple Silicon: frequency not exposed via sysctl
        # NOTE: These are approximate P-core max frequencies; update as new chips release
        chip_name=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
        if [ -z "$chip_name" ]; then
            chip_name=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ {print $2}')
        fi
        case "$chip_name" in
            *"M1"*)           cpu_freq="3.20" ;;
            *"M2"*)           cpu_freq="3.50" ;;
            *"M3"*)           cpu_freq="4.05" ;;
            *"M4"*)           cpu_freq="4.40" ;;
            *)                cpu_freq="N/A" ;;
        esac
    fi
else
    # Linux
    cpu_model="$(lscpu | grep 'Model name' | grep -v 'BIOS' | cut -f 2 -d ':' | awk '{print $1 " "  $2 " " $3 " " $4}')"
    cpu_hypervisor="$(lscpu | grep 'Hypervisor vendor' | cut -f 2 -d ':' | awk '{$1=$1}1')"
    if [ -z "$cpu_hypervisor" ]; then
        cpu_hypervisor="Bare Metal"
    fi

    cpu_cores="$(nproc --all)"
    cpu_cores_per_socket="$(lscpu | grep 'Core(s) per socket' | cut -f 2 -d ':'| awk '{$1=$1}1')"
    cpu_sockets="$(lscpu | grep 'Socket(s)' | cut -f 2 -d ':' | awk '{$1=$1}1')"
    cpu_freq="$(grep 'cpu MHz' /proc/cpuinfo | cut -f 2 -d ':' | awk 'NR==1 { printf "%.2f", $1 / 1000 }')"
fi

# macOS uses "load averages:" (plural), Linux uses "load average:" (singular)
load_avg_1min=$(uptime | awk -F'load averages?: ' '{print $2}' | cut -d ',' -f1 | tr -d ' ')
load_avg_5min=$(uptime | awk -F'load averages?: ' '{print $2}' | cut -d ',' -f2 | tr -d ' ')
load_avg_15min=$(uptime | awk -F'load averages?: ' '{print $2}' | cut -d ',' -f3 | tr -d ' ')

# Memory Information
if [[ "$OSTYPE" == "darwin"* ]]; then
    mem_total_bytes=$(sysctl -n hw.memsize)
    mem_total=$((mem_total_bytes / 1024))  # Convert to KB for consistency

    # Get memory usage from vm_stat (values are in pages)
    page_size=$(vm_stat | head -1 | awk -F'page size of ' '{print $2}' | awk '{print $1}')
    vm_stats=$(vm_stat)
    pages_free=$(echo "$vm_stats" | awk '/Pages free:/ {gsub(/\./,"",$3); print $3}')
    pages_inactive=$(echo "$vm_stats" | awk '/Pages inactive:/ {gsub(/\./,"",$3); print $3}')
    pages_purgeable=$(echo "$vm_stats" | awk '/Pages purgeable:/ {gsub(/\./,"",$3); print $3}')

    # Available = free + inactive + purgeable (memory that can be reclaimed)
    mem_available_pages=$((pages_free + pages_inactive + pages_purgeable))
    mem_available_bytes=$((mem_available_pages * page_size))
    mem_used_bytes=$((mem_total_bytes - mem_available_bytes))
    mem_used=$((mem_used_bytes / 1024))  # Convert to KB
    mem_available=$((mem_available_bytes / 1024))  # Convert to KB
else
    # Linux
    mem_total=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
    mem_available=$(grep 'MemAvailable' /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
fi

mem_percent=$(awk -v used="$mem_used" -v total="$mem_total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
mem_percent=$(printf "%.2f" "$mem_percent")
mem_total_gb=$(echo "$mem_total" | awk '{ printf "%.2f", $1 / (1024 * 1024) }') # (From Ki to Gi units)
mem_available_gb=$(echo "$mem_available" | awk '{ printf "%.2f", $1 / (1024 * 1024) }') # (From Ki to Gi units) Not used currently
mem_used_gb=$(echo "$mem_used" | awk '{ printf "%.2f", $1 / (1024 * 1024) }')

# Disk Information
# Check for ZFS first (works on both Linux and macOS with OpenZFS)
if [[ "$OSTYPE" != "darwin"* ]] && command -v zfs &>/dev/null && grep -q "zfs" /proc/mounts 2>/dev/null; then
    # Linux ZFS
    zfs_present=1
    zfs_health=$(zpool status -x zroot | grep -q "is healthy" && echo "HEALTH O.K." || echo "N/A")
    zfs_available=$(zfs get -o value -Hp available "$zfs_filesystem" 2>/dev/null)
    zfs_used=$(zfs get -o value -Hp used "$zfs_filesystem" 2>/dev/null)
    if [ -n "$zfs_available" ] && [ -n "$zfs_used" ]; then
        zfs_available_gb=$(echo "$zfs_available" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')
        zfs_used_gb=$(echo "$zfs_used" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')
        disk_percent=$(awk -v used="$zfs_used" -v available="$zfs_available" 'BEGIN { printf "%.2f", (used / available) * 100 }')
    else
        zfs_present=0
    fi
elif command -v zpool &>/dev/null && zpool list &>/dev/null 2>&1; then
    # macOS ZFS (OpenZFS)
    zfs_present=1
    zfs_health=$(zpool status -x zroot 2>/dev/null | grep -q "is healthy" && echo "HEALTH O.K." || echo "N/A")
    zfs_available=$(zfs get -o value -Hp available "$zfs_filesystem" 2>/dev/null)
    zfs_used=$(zfs get -o value -Hp used "$zfs_filesystem" 2>/dev/null)
    if [ -n "$zfs_available" ] && [ -n "$zfs_used" ]; then
        zfs_available_gb=$(echo "$zfs_available" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')
        zfs_used_gb=$(echo "$zfs_used" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')
        disk_percent=$(awk -v used="$zfs_used" -v available="$zfs_available" 'BEGIN { printf "%.2f", (used / available) * 100 }')
    else
        zfs_present=0
    fi
fi

if [ "$zfs_present" -eq 0 ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS APFS: use diskutil to get container-level info (matches Finder)
        if command -v diskutil &>/dev/null; then
            container_total=$(diskutil info / 2>/dev/null | awk -F': *' '/Container Total Space/ {print $2}' | awk '{print $1}')
            container_free=$(diskutil info / 2>/dev/null | awk -F': *' '/Container Free Space/ {print $2}' | awk '{print $1}')
        fi

        if [ -n "$container_total" ] && [ -n "$container_free" ]; then
            root_total_gb="$container_total"
            root_available_gb="$container_free"
            root_used_gb=$(awk -v total="$root_total_gb" -v avail="$root_available_gb" 'BEGIN { printf "%.2f", total - avail }')
            disk_percent=$(awk -v used="$root_used_gb" -v total="$root_total_gb" 'BEGIN { printf "%.2f", (used / total) * 100 }')
            # Convert to KB for bar graph calculation
            root_used=$(awk -v gb="$root_used_gb" 'BEGIN { printf "%.0f", gb * 1024 * 1024 }')
            root_total=$(awk -v gb="$root_total_gb" 'BEGIN { printf "%.0f", gb * 1024 * 1024 }')
        else
            # Fallback: standard df for non-APFS macOS
            root_partition="/"
            root_used=$(df -k "$root_partition" | awk 'NR==2 {print $3}')
            root_available=$(df -k "$root_partition" | awk 'NR==2 {print $4}')
            root_total=$((root_used + root_available))
            root_total_gb=$(awk -v total="$root_total" 'BEGIN { printf "%.2f", total / (1024 * 1024) }')
            root_used_gb=$(awk -v used="$root_used" 'BEGIN { printf "%.2f", used / (1024 * 1024) }')
            disk_percent=$(awk -v used="$root_used" -v total="$root_total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
        fi
    else
        # Linux: use df
        root_partition="/"
        root_used=$(df -m "$root_partition" | awk 'NR==2 {print $3}')
        root_total=$(df -m "$root_partition" | awk 'NR==2 {print $2}')
        root_total_gb=$(awk -v total="$root_total" 'BEGIN { printf "%.2f", total / 1024 }')
        root_used_gb=$(awk -v used="$root_used" 'BEGIN { printf "%.2f", used / 1024 }')
        disk_percent=$(awk -v used="$root_used" -v total="$root_total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
    fi
fi

# Last login and Uptime
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses 'last' command
    last_login=$(last -1 "$USER" 2>/dev/null | head -1)
    if [ -n "$last_login" ] && ! echo "$last_login" | grep -q "^$"; then
        last_login_host=$(echo "$last_login" | awk '{print $3}')
        if [[ "$last_login_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            last_login_ip_present=1
            last_login_ip="$last_login_host"
            last_login_time=$(echo "$last_login" | awk '{print $4, $5, $6, $7}')
        else
            last_login_time=$(echo "$last_login" | awk '{print $3, $4, $5, $6}')
        fi
    else
        last_login_time="Never logged in"
    fi

    # macOS uptime doesn't support -p flag, parse standard output
    uptime_raw=$(uptime)
    if echo "$uptime_raw" | grep -q "day"; then
        days=$(echo "$uptime_raw" | sed -E 's/.*up ([0-9]+) day.*/\1/')
        hours=$(echo "$uptime_raw" | sed -E 's/.*day[s]?, +([0-9]+):([0-9]+).*/\1/')
        mins=$(echo "$uptime_raw" | sed -E 's/.*day[s]?, +([0-9]+):([0-9]+).*/\2/')
        sys_uptime="${days}d ${hours}h ${mins}m"
    else
        if echo "$uptime_raw" | grep -qE 'up +[0-9]+:[0-9]+'; then
            hours=$(echo "$uptime_raw" | sed -E 's/.*up +([0-9]+):([0-9]+).*/\1/')
            mins=$(echo "$uptime_raw" | sed -E 's/.*up +([0-9]+):([0-9]+).*/\2/')
            sys_uptime="${hours}h ${mins}m"
        elif echo "$uptime_raw" | grep -qE 'up +[0-9]+ min'; then
            mins=$(echo "$uptime_raw" | sed -E 's/.*up +([0-9]+) min.*/\1/')
            sys_uptime="${mins}m"
        else
            sys_uptime=$(echo "$uptime_raw" | sed -E 's/.*up +([^,]+),.*/\1/')
        fi
    fi
else
    # Linux uses 'lastlog' command
    last_login=$(lastlog -u "$USER")
    last_login_ip=$(echo "$last_login" | awk 'NR==2 {print $3}')

    if [[ "$last_login_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        last_login_ip_present=1
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $6, $7, $10, $8}')
    else
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $4, $5, $8, $6}')
        if [ "$last_login_time" = "in**" ]; then
            last_login_time="Never logged in"
        fi
    fi

    sys_uptime=$(uptime -p | sed 's/up\s*//; s/\s*day\(s*\)/d/; s/\s*hour\(s*\)/h/; s/\s*minute\(s*\)/m/')
fi

# Set current length before graphs get calculated
set_current_len

# Create graphs
cpu_1min_bar_graph=$(bar_graph "$load_avg_1min" "$cpu_cores")
cpu_5min_bar_graph=$(bar_graph "$load_avg_5min" "$cpu_cores")
cpu_15min_bar_graph=$(bar_graph "$load_avg_15min" "$cpu_cores")

mem_bar_graph=$(bar_graph "$mem_used" "$mem_total")

if [ $zfs_present -eq 1 ]; then
    disk_bar_graph=$(bar_graph "$zfs_used" "$zfs_available")
else
    disk_bar_graph=$(bar_graph "$root_used" "$root_total")
fi

# Machine Report
PRINT_HEADER
PRINT_CENTERED_DATA "$report_title"
PRINT_CENTERED_DATA "TR-100 MACHINE REPORT"
PRINT_DIVIDER "top"
PRINT_DATA "OS" "$os_name"
PRINT_DATA "KERNEL" "$os_kernel"
PRINT_DIVIDER
PRINT_DATA "HOSTNAME" "$net_hostname"
PRINT_DATA "MACHINE IP" "$net_machine_ip"
PRINT_DATA "CLIENT  IP" "$net_client_ip"

for dns_num in "${!net_dns_ip[@]}"; do
    PRINT_DATA "DNS  IP $(($dns_num + 1))" "${net_dns_ip[dns_num]}"
done

PRINT_DATA "USER" "$net_current_user"
PRINT_DIVIDER
PRINT_DATA "PROCESSOR" "$cpu_model"
PRINT_DATA "CORES" "$cpu_cores_per_socket vCPU(s) / $cpu_sockets Socket(s)"
PRINT_DATA "HYPERVISOR" "$cpu_hypervisor"
PRINT_DATA "CPU FREQ" "$cpu_freq GHz"
PRINT_DATA "LOAD  1m" "$cpu_1min_bar_graph"
PRINT_DATA "LOAD  5m" "$cpu_5min_bar_graph"
PRINT_DATA "LOAD 15m" "$cpu_15min_bar_graph"

if [ $zfs_present -eq 1 ]; then
    PRINT_DIVIDER
    PRINT_DATA "VOLUME" "$zfs_used_gb/$zfs_available_gb GB [$disk_percent%]"
    PRINT_DATA "DISK USAGE" "$disk_bar_graph"
    PRINT_DATA "ZFS HEALTH" "$zfs_health"
else
    PRINT_DIVIDER
    PRINT_DATA "VOLUME" "$root_used_gb/$root_total_gb GB [$disk_percent%]"
    PRINT_DATA "DISK USAGE" "$disk_bar_graph"
fi

PRINT_DIVIDER
PRINT_DATA "MEMORY" "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"
PRINT_DATA "USAGE" "${mem_bar_graph}"
PRINT_DIVIDER
PRINT_DATA "LAST LOGIN" "$last_login_time"

if [ $last_login_ip_present -eq 1 ]; then
    PRINT_DATA "" "$last_login_ip"
fi

PRINT_DATA "UPTIME" "$sys_uptime"
PRINT_DIVIDER "bottom"
