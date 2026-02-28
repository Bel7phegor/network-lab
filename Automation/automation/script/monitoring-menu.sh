#!/bin/bash
# Location: /automation/script/monitoring-menu.sh

NETWORK_AUTOMATION_DIR="/automation/network-automation"
INVENTORY_FILE="$NETWORK_AUTOMATION_DIR/inventory/hosts"

# Định nghĩa đường dẫn Playbook
PB_DOCKER_DIR="$NETWORK_AUTOMATION_DIR/playbooks/maintenance/docker"
PB_NODE_DIR="$NETWORK_AUTOMATION_DIR/playbooks/monitoring/node_exporter"
PB_PROMTAIL_DIR="$NETWORK_AUTOMATION_DIR/playbooks/monitoring/promtail"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' 

declare -a AVAILABLE_GROUPS
declare -a AVAILABLE_HOSTS
TOTAL_OPTIONS=0

header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        MONITORING MANAGEMENT MENU            ║"
    echo "║      (Docker - Node Exporter - Promtail)     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

error_msg() {
    echo -e "${RED}Error: $1${NC}"
    sleep 2
}

success_msg() {
    echo -e "${GREEN} OK $1${NC}"
    sleep 2
}

get_available_targets() {
    echo -e "${BLUE}Available Linux targets:${NC}"

    local groups=$(grep -E "^\[(internal|dmz)\]" "$INVENTORY_FILE" | sed 's/\[//;s/\]//' | sort -u)

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

    local hosts=$(awk '/\[(internal|dmz)\]/{f=1;next} /^\[/{f=0} f' "$INVENTORY_FILE" \
                  | grep -v "^#" | grep -v "^$" | awk '{print $1}' | sort -u)

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
    echo -e "  ${GREEN}$special_count. all${NC}         - All Linux hosts"
    special_count=$((special_count+1))
    echo -e "  ${GREEN}$special_count. multiple${NC}     - Select multiple hosts"

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

    if [ -n "$selected_hosts" ]; then
        echo "${selected_hosts%,}"
    else
        echo ""
    fi
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
    local playbook_path=$1
    local target=$2
    local tags=$3
    local extra_vars_input=$4

    echo -e "${BLUE}Executing Ansible Playbook...${NC}"
    echo -e "Target: $target | Tags: $tags"
    echo -e "${YELLOW}=========================================${NC}"

    cd $NETWORK_AUTOMATION_DIR

    local cmd="ansible-playbook -i $INVENTORY_FILE $playbook_path -e \"target_hosts=$target\""

    if [ -f "secrets/secrets.yml" ]; then
        cmd="$cmd -e \"@secrets/secrets.yml\" --ask-vault-pass"
    fi

    if [ -n "$tags" ]; then
        cmd="$cmd --tags \"$tags\""
    fi

    if [ -n "$extra_vars_input" ]; then
        cmd="$cmd $extra_vars_input"
    fi

    echo -e "${CYAN}Command: $cmd${NC}"
    
    eval $cmd

    if [ $? -eq 0 ]; then
        success_msg "Operation completed successfully on $target"
    else
        error_msg "Operation failed on $target"
    fi

    echo ""
    read -p "Press Enter to return to menu..." pause
}

install_docker() {
    header
    echo -e "${GREEN}INSTALL DOCKER CE${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi

    echo -e "${CYAN}You selected: $target${NC}"
    read -p "Confirm install Docker? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then echo -e "${YELLOW}Cancelled.${NC}"; return; fi

    run_ansible_playbook "$PB_DOCKER_DIR/docker_lifecycle.yml" "$target" "install" ""
}


install_node_exporter() {
    header
    echo -e "${GREEN}DEPLOY NODE EXPORTER (Metrics)${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi

    echo -e "${CYAN}You selected: $target${NC}"
    read -p "Confirm installation? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then echo -e "${YELLOW}Cancelled.${NC}"; return; fi

    run_ansible_playbook "$PB_NODE_DIR/deploy_node_exporter.yml" "$target" "install" ""
}


install_promtail() {
    header
    echo -e "${GREEN}DEPLOY PROMTAIL (Logs)${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi

    # Hỏi IP Loki
    read -p "Enter Loki Server IP [default: 192.168.254.254]: " loki_ip
    loki_ip=${loki_ip:-192.168.254.254}
    local loki_url="http://$loki_ip:3100/loki/api/v1/push"

    echo -e "${CYAN}You selected: $target | Loki: $loki_url${NC}"
    read -p "Confirm installation? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then echo -e "${YELLOW}Cancelled.${NC}"; return; fi

    local extra="-e \"loki_url=$loki_url\""
    run_ansible_playbook "$PB_PROMTAIL_DIR/deploy_promtail.yml" "$target" "install,config" "$extra"
}

remove_tools() {
    header
    echo -e "${RED}REMOVE MONITORING TOOLS${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then error_msg "Invalid choice!"; return; fi
    if [ "$target" == "multiple" ]; then target=$(select_multiple_hosts); if [ -z "$target" ]; then error_msg "No hosts selected!"; return; fi; fi

    echo ""
    echo "Which component to remove?"
    echo "1. Node Exporter (Metrics)"
    echo "2. Promtail (Logs)"
    echo "3. Docker Engine"
    echo "4. ALL (Clean Wipe)"
    read -p "Choice (1-4): " rm_choice

    read -p "Are you sure you want to remove? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then echo -e "${YELLOW}Cancelled.${NC}"; return; fi

    if [ "$rm_choice" == "1" ] || [ "$rm_choice" == "4" ]; then
        echo -e "${RED}Removing Node Exporter...${NC}"
        run_ansible_playbook "$PB_NODE_DIR/deploy_node_exporter.yml" "$target" "wipe" ""
    fi

    if [ "$rm_choice" == "2" ] || [ "$rm_choice" == "4" ]; then
        echo -e "${RED}Removing Promtail...${NC}"
        run_ansible_playbook "$PB_PROMTAIL_DIR/deploy_promtail.yml" "$target" "wipe" ""
    fi

    if [ "$rm_choice" == "3" ] || [ "$rm_choice" == "4" ]; then
        echo -e "${RED}Removing Docker...${NC}"
        # Giả định playbook docker có tag 'remove' hoặc 'wipe'
        run_ansible_playbook "$PB_DOCKER_DIR/deploy_docker.yml" "$target" "wipe" ""
    fi
}

# Main Menu
main_menu() {
    while true; do
        header
        echo -e "${GREEN}Please select an option:${NC}"
        echo -e "${YELLOW}1.${NC} Install Docker CE (Prerequisite)"
        echo -e "${YELLOW}2.${NC} Deploy Node Exporter (Metrics)"
        echo -e "${YELLOW}3.${NC} Deploy Promtail (Logs)"
        echo -e "${YELLOW}4.${NC} Remove Monitoring/Docker"
        echo -e "${YELLOW}5.${NC} List Available Hosts"
        echo -e "${YELLOW}6.${NC} Exit"
        echo ""
        read -p "Enter your choice (1-6): " choice

        case $choice in
            1) install_docker ;;
            2) install_node_exporter ;;
            3) install_promtail ;;
            4) remove_tools ;;
            5)
                header
                get_available_targets
                read -p "Press Enter to continue..."
                ;;
            6)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                error_msg "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Check Requirements
if [ ! -f "$INVENTORY_FILE" ]; then
    error_msg "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

main_menu
