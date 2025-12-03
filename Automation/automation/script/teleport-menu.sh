#!/bin/bash
# Teleport Management Menu Script
# Location: /automation/script/teleport-menu.sh

# Path configurations
NETWORK_AUTOMATION_DIR="/automation/network-automation"
PLAYBOOK_DIR="$NETWORK_AUTOMATION_DIR/playbooks/teleport"
INVENTORY_FILE="$NETWORK_AUTOMATION_DIR/inventory/hosts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables for menu selection
declare -a AVAILABLE_GROUPS
declare -a AVAILABLE_HOSTS
TOTAL_OPTIONS=0

# Function to display header
header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║          TELEPORT MANAGEMENT MENU            ║"
    echo "║     Automation Script - $(date +%Y-%m-%d) 	       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to display error
error_msg() {
    echo -e "${RED}❌ Error: $1${NC}"
    sleep 2
}

# Function to display success
success_msg() {
    echo -e "${GREEN}✅ $1${NC}"
    sleep 2
}

# Function to get available Linux hosts and groups (only internal group)
get_available_targets() {
    echo -e "${BLUE}Available Linux targets for Agent:${NC}"

    # Chỉ lấy group internal
    local groups=$(grep -E "^\[(internal)\]" "$INVENTORY_FILE" | sed 's/\[//;s/\]//' | sort -u)

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

    # Lấy host thuộc group internal
    local hosts=$(awk '/\[internal\]/{f=1;next}/\[/{f=0}f' "$INVENTORY_FILE" \
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
    echo -e "  ${GREEN}$special_count. multiple${NC}    - Select multiple hosts"

    # Lưu array cho menu
    AVAILABLE_GROUPS=("" "${group_list[@]}")
    AVAILABLE_HOSTS=("" "${group_list[@]}" "${host_list[@]}")
    TOTAL_OPTIONS=$special_count
}

# Function to select multiple hosts
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

# Function to get target by number
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

# Function to run ansible playbook
run_ansible_playbook() {
    local playbook=$1
    local target=$2

    echo -e "${BLUE}Running: ansible-playbook -i $INVENTORY_FILE $playbook -e \"target_hosts=$target\" -e \"@secrets/secrets.yml\" --ask-vault-pass${NC}"
    echo -e "${YELLOW}=========================================${NC}"

    cd $NETWORK_AUTOMATION_DIR

    if [ -f "secrets/secrets.yml" ]; then
        ansible-playbook -i $INVENTORY_FILE $PLAYBOOK_DIR/$playbook \
            -e "target_hosts=$target" \
            -e "@secrets/secrets.yml" \
            --ask-vault-pass
    else
        ansible-playbook -i $INVENTORY_FILE $PLAYBOOK_DIR/$playbook \
            -e "target_hosts=$target"
    fi

    if [ $? -eq 0 ]; then
        success_msg "Operation completed successfully on $target"
    else
        error_msg "Operation failed on $target"
    fi

    echo ""
    read -p "👉 Press Enter to return to menu..." pause
}

# Install Teleport
install_teleport() {
    header
    echo -e "${GREEN}🚀 INSTALL TELEPORT${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then
        error_msg "Invalid choice!"
        return
    fi

    if [ "$target" == "multiple" ]; then
        target=$(select_multiple_hosts)
        if [ -z "$target" ]; then
            error_msg "No hosts selected!"
            return
        fi
    fi

    echo -e "${CYAN}You selected: $target${NC}"
    read -p "Confirm installation? (y/N): " confirm
    confirm=${confirm:-N}

    if [[ $confirm =~ ^[Yy]$ ]]; then
        run_ansible_playbook "teleport-automation.yaml" "$target"
    else
        echo -e "${YELLOW}Installation cancelled.${NC}"
    fi
}

# Remove Teleport
remove_teleport() {
    header
    echo -e "${RED}🗑️ REMOVE TELEPORT${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    get_available_targets
    echo ""
    read -p "Enter your choice (1-$TOTAL_OPTIONS): " choice

    target=$(get_target_by_number $choice)
    if [ -z "$target" ]; then
        error_msg "Invalid choice!"
        return
    fi

    if [ "$target" == "multiple" ]; then
        target=$(select_multiple_hosts)
        if [ -z "$target" ]; then
            error_msg "No hosts selected!"
            return
        fi
    fi

    echo -e "${CYAN}You selected: $target${NC}"
    read -p "Confirm removal? (y/N): " confirm
    confirm=${confirm:-N}

    if [[ $confirm =~ ^[Yy]$ ]]; then
        run_ansible_playbook "teleport-remove.yaml" "$target"
    else
        echo -e "${YELLOW}Removal cancelled.${NC}"
    fi
}

# Main Menu
main_menu() {
    while true; do
        header
        echo -e "${GREEN}Please select an option:${NC}"
        echo -e "${YELLOW}1.${NC} 📦  Install Teleport"
        echo -e "${YELLOW}2.${NC} 🗑️  Remove Teleport"
        echo -e "${YELLOW}3.${NC} 📋  List Available Hosts"
        echo -e "${YELLOW}4.${NC} 🚪  Exit"
        echo ""
        read -p "Enter your choice (1-4): " choice

        case $choice in
            1) install_teleport ;;
            2) remove_teleport ;;
            3)
                header
                get_available_targets
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "${GREEN}👋 Goodbye!${NC}"
                exit 0
                ;;
            *)
                error_msg "Invalid choice. Please try again."
                ;;
        esac
    done
}

if [ ! -f "$INVENTORY_FILE" ]; then
    error_msg "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

if [ ! -f "$PLAYBOOK_DIR/teleport-automation.yaml" ] || [ ! -f "$PLAYBOOK_DIR/teleport-remove.yaml" ]; then
    error_msg "Playbook files not found in $PLAYBOOK_DIR"
    exit 1
fi

main_menu

