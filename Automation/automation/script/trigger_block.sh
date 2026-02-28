#!/bin/bash
ATTACKER_IP=$1
LOG_FILE="/var/log/auto-block.log"

if [[ -z "$ATTACKER_IP" ]]; then
  echo "$(date) - Error: No IP received" >> $LOG_FILE
  exit 1
fi

echo "$(date) - 🚨 ALERT: Received request to block IP: $ATTACKER_IP" >> $LOG_FILE

# Chạy Ansible Playbook
cd /automation/network-automation
ansible-playbook playbooks/security/block_ip.yml \
  -i inventory/hosts \
  --extra-vars "target_ip=$ATTACKER_IP" >> $LOG_FILE 2>&1
