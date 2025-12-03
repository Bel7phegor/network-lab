#!/bin/bash

WORK_DIR="/automation/network-automation"
INVENTORY_FILE="$WORK_DIR/inventory/hosts"
METRIC_FILE="/var/lib/node_exporter/textfile_collector/auto_backup_status.prom"
LOG_FILE="/var/log/backups_auto/auto_backup.log"

# Initialize
mkdir -p "$(dirname "$METRIC_FILE")" "$(dirname "$LOG_FILE")"
> "$METRIC_FILE"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

backup_host() {
  local host="$1" playbook="$2" system_type="$3"
  local start_time=$(date +%s)
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') - === BACKUP STARTED ==="
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting backup for $system_type: $host"
  
  log "Starting backup for $system_type: $host"
  
  ansible_output=$(ansible-playbook "$playbook" -i "$INVENTORY_FILE" -l "$host" 2>&1)
  local result=$?
  local duration=$(( $(date +%s) - start_time ))

  echo "$ansible_output"
  
  if [ $result -eq 0 ]; then
    status_msg="Backup SUCCEEDED for $host (Duration: ${duration}s)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $status_msg"
    log "$status_msg"
    echo "auto_backup_status{host=\"$host\",system=\"$system_type\",mode=\"auto\",timestamp=\"$timestamp\"} 0" >> "$METRIC_FILE"
    echo "auto_backup_duration{host=\"$host\",system=\"$system_type\"} $duration" >> "$METRIC_FILE"
  else
    status_msg="Backup FAILED for $host (Duration: ${duration}s)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $status_msg"
    log "$status_msg"
    echo "auto_backup_status{host=\"$host\",system=\"$system_type\",mode=\"auto\",timestamp=\"$timestamp\"} 1" >> "$METRIC_FILE"
    echo "$ansible_output" | grep -A10 'PLAY RECAP' >> "$LOG_FILE"
  fi
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') - === BACKUP COMPLETED ==="
}

# Main process
echo "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO BACKUP STARTED ==="
log "=== AUTO BACKUP STARTED ==="

# Backup pfSense
awk '/^\[pfsense\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
  backup_host "$host" "$WORK_DIR/playbooks/backup/pfsense_backup.yml" "pfsense"
done

# Backup switches
awk '/^\[switches\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
  backup_host "$host" "$WORK_DIR/playbooks/backup/switch_backup.yml" "switch"
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO BACKUP COMPLETED ==="
  echo "Log file: $LOG_FILE"
  echo "Metrics file: $METRIC_FILE"