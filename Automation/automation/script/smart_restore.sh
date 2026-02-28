#!/bin/bash
source /automation/configs/telegram.conf
APPROVAL_DB="/automation/configs/restore_approvals.db"
LOG_FILE="/var/log/restore_operations.log"

# Function to log messages with timestamp
# Hàm ghi log với thời gian
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Send restore approval request to Telegram
# Gửi yêu cầu phê duyệt restore tới Telegram
request_approval() {
    local host="$1" backup="$2"
    log "Sending restore request for host: $host with backup: $backup"
    
    local message="[RESTORE REQUEST] Cần restore host: $host từ backup: $(basename "$backup")"

    # Send message with inline keyboard
    # Gửi message với bàn phím inline
    local response=$(curl -sX POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -H "Content-Type: application/json" \
        -d '{
            "chat_id": "'"$CHAT_ID"'",
            "text": "'"$message"'",
            "parse_mode": "markdown",
            "reply_markup": {
                "inline_keyboard": [
                    [
                        {"text": "✅ Approve", "callback_data": "approve_'"$host"'"},
                        {"text": "❌ Reject", "callback_data": "reject_'"$host"'"}
                    ]
                ]
            }
        }')

    # Validate API response
    # Kiểm tra phản hồi từ API
    if ! message_id=$(echo "$response" | jq -r '.result.message_id'); then
        log "ERROR: Failed to send Telegram message for host: $host - Response: $response"
        return 1
    fi

    # Store request in database with transaction
    # Lưu yêu cầu vào database sử dụng transaction
    sqlite3 "$APPROVAL_DB" <<EOF
BEGIN TRANSACTION;
INSERT OR REPLACE INTO approvals VALUES(
    '$host',
    '$backup',
    'pending',
    '$message_id',
    datetime('now'),
    NULL,
    NULL,
    NULL
);
COMMIT;
EOF

    log "Successfully sent request for host: $host (Message ID: $message_id)"
}

# Check if restore was approved
# Kiểm tra xem restore đã được phê duyệt chưa
check_approval() {
    local host="$1"
    log "Checking approval status for host: $host"
    
    # Get approval status from database
    # Lấy trạng thái phê duyệt từ database
    local result=$(sqlite3 -separator '|' "$APPROVAL_DB" \
        "SELECT status, approved_by FROM approvals WHERE host='$host'")

    IFS='|' read -r status approved_by <<< "$result"
    
    if [ "$status" = "approved" ]; then
        log "Host $host approved by user $approved_by"
        return 0
    else
        log "Host $host not approved or still pending"
        return 1
    fi
}

# Execute the restore process
# Thực hiện quá trình restore
execute_restore() {
    local host="$1"
    log "Starting restore process for host: $host"
    
    local backup_file=$(sqlite3 "$APPROVAL_DB" \
        "SELECT backup_file FROM approvals WHERE host='$host'")

    # Verify backup file exists
    # Kiểm tra file backup tồn tại
    if [ ! -f "$backup_file" ]; then
        log "ERROR: Backup file not found for host: $host - File: $backup_file"
        return 1
    fi

    # Determine playbook based on host type
    # Xác định playbook dựa trên loại host
    case "$host" in
        *pfsense*) 
            playbook="pfsense_restore.yml"
            log "Using pfsense playbook for host: $host"
            ;;
        *)         
            playbook="switch_restore.yml"
            log "Using switch playbook for host: $host"
            ;;
    esac

    # Run ansible playbook with error handling
    # Chạy ansible playbook với xử lý lỗi
    if ansible-playbook "/automation/network-automation/playbooks/restore/$playbook" \
        -l "$host" \
        -e "backup_file=$backup_file"; then
        log "Successfully restored host: $host"
        return 0
    else
        log "ERROR: Restore failed for host: $host"
        return 1
    fi
}

# Main execution
# Xử lý chính
case "$1" in
    --request)
        if [ $# -ne 3 ]; then
            echo "Usage: $0 --request <host> <backup_file>"
            exit 1
        fi
        request_approval "$2" "$3"
        ;;
    --approve-check)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 --approve-check <host>"
            exit 1
        fi
        if check_approval "$2"; then
            if execute_restore "$2"; then
                echo "Restore completed successfully for $2"
                exit 0
            else
                echo "Restore failed for $2" >&2
                exit 1
            fi
        else
            echo "Restore not approved for $2" >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage:"
        echo "  $0 --request <host> <backup_file>"
        echo "  $0 --approve-check <host>"
        exit 1
        ;;
esac
