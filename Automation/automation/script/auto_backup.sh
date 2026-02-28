#!/bin/bash

WORK_DIR="/automation/network-automation"
INVENTORY_FILE="$WORK_DIR/inventory/hosts"
METRIC_FILE="/var/lib/node_exporter/textfile_collector/auto_backup_status.prom"
LOG_FILE="/var/log/backups_auto/auto_backup.log"
TEMP_OUT="/tmp/ansible_backup_output.txt"

mkdir -p "$(dirname "$METRIC_FILE")" "$(dirname "$LOG_FILE")"
> "$METRIC_FILE"

log_to_file() {
  echo "$1" >> "$LOG_FILE"
}

backup_host() {
  local host="$1" playbook="$2" system_type="$3"
  local start_time=$(date +%s)
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  ansible-playbook "$playbook" -i "$INVENTORY_FILE" -l "$host" > "$TEMP_OUT" 2>&1
  
  local result=$?
  local duration=$(( $(date +%s) - start_time ))
  local end_timestamp_unix=$(date +%s)
  
  ansible_output=$(cat "$TEMP_OUT")

  if [ $result -eq 0 ]; then
    relevant_task=$(sed -n '/TASK \[.*Show archive.*\].*/,/}/p' "$TEMP_OUT")
    
    play_recap=$(grep -A 5 "PLAY RECAP" "$TEMP_OUT")
    
    status_summary="$timestamp - SUCCEEDED: $host | Duration: ${duration}s"

    echo "$relevant_task"
    echo ""
    echo "$play_recap"
    echo "$status_summary"
    echo "----------------------------------------------------------------"

    log_to_file "$relevant_task"
    log_to_file "$play_recap"
    log_to_file "$status_summary"
    log_to_file "----------------------------------------------------------------"

    echo "auto_backup_status{host=\"$host\",system=\"$system_type\",error=\"None\",timestamp=\"$timestamp\"} 0" >> "$METRIC_FILE"
    echo "auto_backup_duration_seconds{host=\"$host\",system=\"$system_type\"} $duration" >> "$METRIC_FILE"
    echo "auto_backup_last_run_seconds{host=\"$host\",system=\"$system_type\"} $end_timestamp_unix" >> "$METRIC_FILE"

  else
    error_block=$(grep -B 1 -A 6 "fatal: \[" "$TEMP_OUT")
    play_recap=$(grep -A 5 "PLAY RECAP" "$TEMP_OUT")
    raw_error=$(echo "$ansible_output" | grep -oP '(?<="msg": ").*?(?=")' | tail -1)
    if [ -z "$raw_error" ]; then raw_error=$(echo "$ansible_output" | grep "fatal:" | sed 's/.*fatal:.*=> //g'); fi
    if [ -z "$raw_error" ]; then raw_error="Unknown Error (Check Log)"; fi
    clean_error=$(echo "$raw_error" | tr -d '"' | tr -d '{}' | tr '\n' ' ' | sed 's/  */ /g' | cut -c 1-200)

    status_summary="$timestamp - FAILED: $host | Duration: ${duration}s"
    reason_msg="$timestamp - Reason: $clean_error"

    echo "$error_block"
    echo ""
    echo "$play_recap"
    echo "$status_summary"
    echo "$reason_msg"
    echo "----------------------------------------------------------------"

    log_to_file "$error_block"
    log_to_file "$play_recap"
    log_to_file "$status_summary"
    log_to_file "$reason_msg"
    log_to_file "----------------------------------------------------------------"

    echo "auto_backup_status{host=\"$host\",system=\"$system_type\",error=\"$clean_error\",timestamp=\"$timestamp\"} 1" >> "$METRIC_FILE"
    echo "auto_backup_duration_seconds{host=\"$host\",system=\"$system_type\"} $duration" >> "$METRIC_FILE"
    echo "auto_backup_last_run_seconds{host=\"$host\",system=\"$system_type\"} $end_timestamp_unix" >> "$METRIC_FILE"
  fi
  
  rm -f "$TEMP_OUT"
}

# --- MAIN PROCESS ---
echo "================================================================"
echo "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO BACKUP STARTED ==="
echo "================================================================"
log_to_file "================================================================"
log_to_file "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO BACKUP STARTED ==="

if [ -f "$INVENTORY_FILE" ]; then
    # Backup pfSense
    awk '/^\[pfsense\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
      backup_host "$host" "$WORK_DIR/playbooks/backup/pfsense_backup.yml" "pfsense"
    done

    # Backup switches
    awk '/^\[switches\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
      backup_host "$host" "$WORK_DIR/playbooks/backup/switch_backup.yml" "switch"
    done
else
    echo "ERROR: Inventory file not found at $INVENTORY_FILE"
    log_to_file "ERROR: Inventory file not found at $INVENTORY_FILE"
fi

echo "Metrics file updated: $METRIC_FILE"
echo "Full Logs: $LOG_FILE"
echo "================================================================"
