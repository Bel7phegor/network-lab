#!/bin/bash

WORK_DIR="/automation/network-automation"
INVENTORY_FILE="$WORK_DIR/inventory/hosts"
METRIC_FILE="/var/lib/node_exporter/textfile_collector/manual_backup_status.prom"
LOG_FILE="/var/log/backups_auto/manual_backup.log"

# Initialize
mkdir -p "$(dirname "$METRIC_FILE")" "$(dirname "$LOG_FILE")"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

backup_host() {
  local host="$1" playbook="$2" system_type="$3"
  local start_time=$(date +%s)
  local timestamp=$(date +%s)
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') - === BACKUP STARTED ==="
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting manual backup for $system_type: $host"
  log "Starting manual backup for $system_type: $host"
  
  local tmp_file="${METRIC_FILE}.tmp"
  [ -f "$METRIC_FILE" ] && grep -vE "(host=\"$host\"|timestamp)" "$METRIC_FILE" > "$tmp_file" || touch "$tmp_file"
  
  ansible_output=$(ansible-playbook "$playbook" -i "$INVENTORY_FILE" -l "$host" 2>&1)
  local result=$?
  local duration=$(( $(date +%s) - start_time ))

  echo "$ansible_output"
  
  if [ $result -eq 0 ]; then
    status_msg="✅ Backup SUCCEEDED for $host (Duration: ${duration}s)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $status_msg"
    log "$status_msg"
    echo "manual_backup_status{host=\"$host\",system=\"$system_type\",mode=\"manual\",timestamp="\$timestamp\"} 0" >> "$tmp_file"
    echo "manual_backup_duration{host=\"$host\",system=\"$system_type\"} $duration" >> "$tmp_file"
  else
    status_msg="❌ Backup FAILED for $host (Duration: ${duration}s)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $status_msg"
    log "$status_msg"
    echo "manual_backup_status{host=\"$host\",system=\"$system_type\",mode=\"manual\",timestamp="\$timestamp\"} 1" >> "$tmp_file"
    
    echo "$ansible_output" | grep -A10 'PLAY RECAP' >> "$LOG_FILE"
  fi
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') - === BACKUP COMPLETED ==="
  mv "$tmp_file" "$METRIC_FILE"
}

select_host() {
  local group="$1" system_type="$2"
  mapfile -t HOSTS < <(awk "/^\[$group\]/ {f=1; next} /^\[/ {f=0} f && NF {print \$1}" "$INVENTORY_FILE")

  [ ${#HOSTS[@]} -eq 0 ] && echo "No $system_type hosts found!" && return 1

  echo "Available $system_type hosts:"
  for i in "${!HOSTS[@]}"; do
    echo "$((i+1)) - ${HOSTS[$i]}"
  done
  echo "$(( ${#HOSTS[@]} + 1 )) - All $system_type hosts"

  read -p "Select host to backup: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  
  if [ "$choice" -le "${#HOSTS[@]}" ]; then
    selected_hosts=("${HOSTS[$((choice-1))]}")
  elif [ "$choice" -eq $((${#HOSTS[@]}+1)) ]; then
    selected_hosts=("${HOSTS[@]}")
  else
    return 1
  fi
}


# Main menu
while true; do
  clear
  echo "=== MANUAL BACKUP MENU ==="
  echo "1) Backup pfSense"
  echo "2) Backup Switch" 
  echo "3) Backup All Devices"
  echo "0) Exit"
  read -p "Select: " option

  case $option in
    1)
      if select_host "pfsense" "pfsense"; then
        for host in "${selected_hosts[@]}"; do
          backup_host "$host" "$WORK_DIR/playbooks/pfsense_backup.yml" "pfsense"
        done
      fi
      ;;
    2)
      if select_host "switches" "switch"; then
        for host in "${selected_hosts[@]}"; do
          backup_host "$host" "$WORK_DIR/playbooks/switch_backup.yml" "switch"
        done
      fi
      ;;
    3)
      awk '/^\[pfsense\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
        backup_host "$host" "$WORK_DIR/playbooks/pfsense_backup.yml" "pfsense"
      done
      awk '/^\[switches\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
        backup_host "$host" "$WORK_DIR/playbooks/switch_backup.yml" "switch"
      done
      ;;
    0) exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac

  echo ""
  echo "=== BACKUP FINISHED ==="
  echo "Log file: $LOG_FILE"
  echo "Metrics file: $METRIC_FILE"
  read -p "Press Enter to continue..."
done