#!/bin/bash

WORK_DIR="/automation/network-automation"
INVENTORY_FILE="$WORK_DIR/inventory/hosts"
RESTORE_LOG="/var/log/backups_auto/auto_restore.log"
BACKUP_ROOT="/backups"  # Cùng thư mục với playbook backup
METRIC_FILE="/var/lib/node_exporter/textfile_collector/auto_restore_status.prom"

# Khởi tạo
mkdir -p "$(dirname "$RESTORE_LOG")" "$(dirname "$METRIC_FILE")"
> "$METRIC_FILE"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$RESTORE_LOG"
}

find_latest_backup() {
  local host="$1" system_type="$2"
  
  case $system_type in
    "pfsense")
      # Tìm thư mục mới nhất theo pattern YYYYMMDD-HHMMSS
      latest_dir=$(ls -td "$BACKUP_ROOT/pfsense/$host"/[0-9]* 2>/dev/null | head -1)
      [ -n "$latest_dir" ] && echo "$latest_dir/$(basename "$latest_dir").tar.gz"
      ;;
    "switch")
      # Tìm thư mục mới nhất theo pattern YYYYMMDD-HHMMSS-hostname
      latest_dir=$(ls -td "$BACKUP_ROOT/switches/$host"/[0-9]*-"$host" 2>/dev/null | head -1)
      [ -n "$latest_dir" ] && echo "$latest_dir/backup-run.tar.gz"
      ;;
    *)
      echo ""
      ;;
  esac
}

restore_host() {
  local host="$1" system_type="$2"
  
  # 1. Tìm backup mới nhất (như đã triển khai)
  latest_backup=$(find_latest_backup "$host" "$system_type")

  # 2. Kiểm tra điều kiện restore (ví dụ: config bị thay đổi)
  if check_config_drift "$host"; then
    # 3. Gửi cảnh báo và đợi xác nhận
    send_alert "⚠️ Cần restore $host. Backup mới nhất: $(basename "$latest_backup")"
    
    if wait_for_approval; then  # Yêu cầu confirm từ admin
      # 4. Thực hiện restore sau khi được phê duyệt
      execute_restore "$host" "$latest_backup"
    fi
  fi
}

# Main process
echo "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO RESTORE STARTED ==="
log "=== AUTO RESTORE STARTED ==="

# Restore logic có thể trigger bằng:
# 1. File flag (ví dụ khi phát hiện config bị thay đổi)
# 2. Hoặc restore tất cả thiết bị định kỳ

# Ví dụ restore tất cả pfSense
awk '/^\[pfsense\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
  restore_host "$host" "pfsense"
done

# Ví dụ restore tất cả switch
awk '/^\[switches\]/{f=1;next} /^\[/{f=0} f && NF{print $1}' "$INVENTORY_FILE" | while read -r host; do
  restore_host "$host" "switch"
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - === AUTO RESTORE COMPLETED ==="
log "=== AUTO RESTORE COMPLETED ==="
echo "Restore log: $RESTORE_LOG"
echo "Metrics: $METRIC_FILE"