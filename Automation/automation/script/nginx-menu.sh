#!/bin/bash
# Nginx Management Menu Script
# Location: /automation/script/nginx-menu.sh

# --- CONFIGURATIONS ---
NETWORK_AUTOMATION_DIR="/automation/network-automation"
PLAYBOOK_DIR="$NETWORK_AUTOMATION_DIR/playbooks/nginx"
INVENTORY_FILE="$NETWORK_AUTOMATION_DIR/inventory/hosts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
declare -a AVAILABLE_GROUPS
declare -a AVAILABLE_HOSTS
TOTAL_OPTIONS=0

header() {
    clear
    echo -e "${CYAN}"
    echo "================================================"
    echo "           NGINX MANAGEMENT MENU                "
    echo "       Automation Script - $(date +%Y-%m-%d)    "
    echo "================================================"
    echo -e "${NC}"
}

error_msg() { echo -e "${RED}[!] Error: $1${NC}"; sleep 2; }
success_msg() { echo -e "${GREEN}[OK] $1${NC}"; sleep 2; }

get_available_targets() {
    echo -e "${BLUE}Available Linux targets for Nginx:${NC}"

    # 1. Lấy Groups
    local groups=$(grep -E "^\[(dmz|internal)\]" "$INVENTORY_FILE" | sed 's/\[//;s/\]//' | sort -u)

    echo -e "${YELLOW}Groups:${NC}"
    local group_count=0
    local group_list=()
    while IFS= read -r group; do
        if [ -n "$group" ]; then
            group_count=$((group_count+1))
            group_list+=("$group")
            echo -e "  ${GREEN}$group_count. $group${NC}"
        fi
    done <<< "$groups"

    echo ""
    echo -e "${YELLOW}Individual hosts:${NC}"
    local host_count=$group_count
    local host_list=()

    # 2. Lấy Hosts (Fixed awk)
    local hosts=$(awk '/\[(dmz|internal)\]/{flag=1; next} /^\[/{flag=0} flag && !/^$/ && !/^#/ {print $1}' "$INVENTORY_FILE" | sort -u)

    while IFS= read -r host; do
        if [ -n "$host" ]; then
            host_count=$((host_count+1))
            host_list+=("$host")
            local ip=$(grep "^$host" "$INVENTORY_FILE" | grep -oP 'ansible_host=\K[^ ]+' | head -1)
            if [ -n "$ip" ]; then
                echo -e "  ${GREEN}$host_count. $host${NC} - ${YELLOW}$ip${NC}"
            else
                echo -e "  ${GREEN}$host_count. $host${NC}"
            fi
        fi
    done <<< "$hosts"

    echo ""
    echo -e "${YELLOW}Special options:${NC}"
    local special_count=$((host_count+1))
    echo -e "  ${GREEN}$special_count. all${NC}         - All Linux hosts (DMZ & Internal)"
    special_count=$((special_count+1))
    echo -e "  ${GREEN}$special_count. multiple${NC}    - Select multiple hosts"

    AVAILABLE_GROUPS=("" "${group_list[@]}")
    AVAILABLE_HOSTS=("" "${group_list[@]}" "${host_list[@]}")
    TOTAL_OPTIONS=$special_count
}

select_multiple_hosts() {
    echo -e "${CYAN}Select multiple hosts (comma separated numbers):${NC}"
    local count=0
    for i in $(seq $((${#AVAILABLE_GROUPS[@]})) $((${#AVAILABLE_HOSTS[@]}-1))); do
        count=$((count+1))
        local host="${AVAILABLE_HOSTS[$i]}"
        local ip=$(grep "^$host" "$INVENTORY_FILE" | grep -oP 'ansible_host=\K[^ ]+' | head -1)
        if [ -n "$ip" ]; then
            echo -e "  ${GREEN}$count. $host${NC} - ${YELLOW}$ip${NC}"
        else
            echo -e "  ${GREEN}$count. $host${NC}"
        fi
    done

    echo ""
    read -p "Enter numbers (e.g., 1,3,4): " numbers
    local selected_hosts=""
    IFS=',' read -ra num_array <<< "$numbers"
    for num in "${num_array[@]}"; do
        local actual_index=$((num + ${#AVAILABLE_GROUPS[@]}))
        if [ $actual_index -le $((${#AVAILABLE_HOSTS[@]}-1)) ]; then
            selected_hosts+="${AVAILABLE_HOSTS[$actual_index]},"
        fi
    done
    if [ -n "$selected_hosts" ]; then echo "${selected_hosts%,}"; else echo ""; fi
}

get_target_by_number() {
    local choice=$1
    if [ $choice -le $((${#AVAILABLE_GROUPS[@]}-1)) ]; then
        echo "${AVAILABLE_GROUPS[$choice]}"
    elif [ $choice -le $((${#AVAILABLE_HOSTS[@]}-1)) ]; then
        echo "${AVAILABLE_HOSTS[$choice]}"
    elif [ $choice -eq $((TOTAL_OPTIONS-1)) ]; then
        echo "all"
    elif [ $choice -eq $TOTAL_OPTIONS ]; then
        echo "multiple"
    else
        echo ""
    fi
}

run_ansible_playbook() {
    local playbook=$1
    local target=$2
    echo -e "${BLUE}Running Playbook: $playbook${NC}"
    echo -e "${BLUE}Target: $target${NC}"
    echo -e "${YELLOW}-----------------------------------------${NC}"
    cd $NETWORK_AUTOMATION_DIR
    
    # Construct command
    local cmd="ansible-playbook -i $INVENTORY_FILE \"$PLAYBOOK_DIR/$playbook\" -e \"target_hosts=$target\""
    
    if [ -f "secrets/secrets.yml" ]; then
        cmd="$cmd -e \"@secrets/secrets.yml\" --ask-vault-pass"
    fi

    # Display Command
    echo -e "${YELLOW}Executing Command:${NC}"
    echo -e "${GREEN}$cmd${NC}"
    echo -e "${YELLOW}-----------------------------------------${NC}"

    # Execute
    eval $cmd

    if [ $? -eq 0 ]; then success_msg "Playbook completed successfully."; else error_msg "Playbook failed."; fi
    echo ""; read -p ">> Press Enter to return to menu..." pause
}

install_nginx() {
    header; echo -e "${GREEN}[+] INSTALL NGINX${NC}"; echo -e "${YELLOW}-----------------------------------------${NC}"
    get_available_targets; echo ""; read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice
    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi
    echo -e "${CYAN}Target: $target${NC}"
    read -p "Confirm install? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then run_ansible_playbook "nginx-install.yaml" "$target"; else echo "Cancelled."; fi
}

remove_nginx() {
    header; echo -e "${RED}[-] REMOVE NGINX${NC}"; echo -e "${YELLOW}-----------------------------------------${NC}"
    get_available_targets; echo ""; read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice
    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi
    echo -e "${CYAN}Target: $target${NC}"
    read -p "Confirm remove? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then run_ansible_playbook "nginx-remove.yaml" "$target"; else echo "Cancelled."; fi
}

check_status() {
    header; echo -e "${BLUE}[?] NGINX STATUS CHECK${NC}"; echo -e "${YELLOW}-----------------------------------------${NC}"
    get_available_targets; echo ""; read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice
    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi
    echo -e "${CYAN}Target: $target${NC}"
    run_ansible_playbook "nginx-status.yaml" "$target"
}

main_menu() {
    while true; do
        header
        echo -e "  1. Install Nginx"
        echo -e "  2. Remove Nginx"
        echo -e "  3. Check Status"
        echo -e "  4. List Available Hosts"
        echo -e "  5. Exit"
        echo ""
        read -p "Enter choice (1-5): " choice
        case $choice in
            1) install_nginx ;;
            2) remove_nginx ;;
            3) check_status ;;
            4) header; get_available_targets; read -p "Press Enter..." ;;
            5) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) error_msg "Invalid choice." ;;
        esac
    done
}

if [ ! -f "$INVENTORY_FILE" ]; then error_msg "Inventory file not found: $INVENTORY_FILE"; exit 1; fi
main_menu
