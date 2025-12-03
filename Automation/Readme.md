# Cài Ansible
- Cài Ansible bản mới nhất từ Ansible PPA 
    ```
    sudo apt update
    sudo apt install software-properties-common -y
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install ansible -y
    ansible --version
    ```
- Cài thêm các Python modules cần thiết
    ```
    sudo apt install python3-pip -y
    pip3 --version
    pip3 install ansible netmiko napalm paramiko
    ```
# Cấu trúc thư mục chuẩn gợi ý cho Ansible project:

    network-automation/
    ├── ansible.cfg
    ├── inventory/
    │   ├── hosts           # File khai báo các thiết bị (inventory)
    │   └── group_vars/
    │       └── routers.yml # Biến dùng chung cho nhóm thiết bị
    ├── playbooks/
    │   ├── config_hostname.yml
    │   ├── backup_config.yml
    │   └── ...
    ├── roles/              # Dùng khi dự án lớn
    │   └── cisco_config/
    │       ├── tasks/
    │       │   └── main.yml
    │       ├── templates/
    │       ├── defaults/
    │       └── ...
    ├── vars/
    │   └── global_vars.yml # Biến dùng chung toàn hệ thống
    └── README.md

# Cấu hình thiết bị
## Thiết bị mạng 
1. Bật SSH
- Ansible kết nối đến router/switch chủ yếu qua SSH, vì vậy phải bật SSH:
    ```
    conf t
    ip domain-name anphuc.vn

    username anphuc privilege 15 secret anphuc1231

    crypto key generate rsa 
    1024
    
    ip ssh version 2
    line vty 0 4
    login local
    transport input ssh
    ```
2. Tạo tài khoản user/password
    > username anphuc privilege 15 secret anphuc1231
## Cấu hình 
### Tạo thư mục lưu trữ cấu hình `Ansible` và thư mục `backups` để lưu trữ dữ liệu được tự động hóa lấy về.

    sudo mkdir -p /automation/network-automation/inventory /automation/network-automation/playbooks
    sudo chown -R anphuc:anphuc /automation
    sudo mkdir -p /backups 
    sudo chown -R anphuc:anphuc /backups

### Tạo file `ansible.cfg`


    [defaults]
    inventory = ./inventory/hosts
    host_key_checking = False
    timeout = 30

### Tạo file `inventory/hosts`
- Phải cấu hình ở `/etc/hosts` để định danh được các tên thuộc địa chỉ ip nào
    > sudo vi /etc/hosts
    ```
    127.0.0.1 localhost
    192.168.254.1 DMZ
    10.10.30.1 pfsense
    ```
- Tạo file `inventory/hosts` 
  - vi inventory/hosts

    ```
    [switches]
    DMZ ansible_hosts=192.168.254.1 ansible_user=anphuc ansible_password=anphuc1231 ansible_network_os=ios
    [pfsense]
    pfsense ansible_hosts=10.10.30.1 ansible_user=anphuc ansible_password=Anphuc@1231 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    ```
### Tạo file `playbooks/backup..` để lấy dữ liệu backup từ các thiết bị về 
- vi backup_switch_config.yml
    ```
    ---
  - name: Backup config from switches
    hosts: switches
    gather_facts: no
    connection: network_cli

    tasks:
      - name: Get running config
        ansible.netcommon.cli_command:
            command: show running-config
        register: config_output

      - name: Debug output to verify
        debug:
            var: config_output.stdout

      - name: Save config to local file
        delegate_to: localhost
        ansible.builtin.copy:
            content: "{{ config_output.stdout  }}"
            dest: "/backups/switches/{{ inventory_hostname }}-running-config.txt"

    ```
- vi backup_pfsense.yml
    ```
    ---
  - name: Backup pfSense configuration
    hosts: pfsense
    gather_facts: no
    become: false

    tasks:
      - name: Fetch pfSense config.xml
        ansible.builtin.shell: cat /cf/conf/config.xml
        register: config_data

      - name: Save config to local file
        delegate_to: localhost
        ansible.builtin.copy:
            content: "{{ config_data.stdout }}"
            dest: "/backups/pfsense-config-{{ inventory_hostname }}.xml"

    ```
- Chạy playbook

    ```
    ansible-playbook playbooks/backup_pfsense.yml playbooks/backup_switch_config
    ```
# Mã hóa và giải mã file bằng Ansible Vault
## Mã hóa 
- Câu lệnh: `ansible-vault encrypt /backups/pfsense-config-pfSense.xml`
- Nó sẽ yêu cầu nhập mật khẩu Vault 2 lần (mật khẩu này dùng để giải mã về sau).
## Giải mã file
- Câu lệnh: `ansible-vault decrypt /backups/pfsense-config-pfSense.xml`
- Sau khi giải mã xong, file sẽ trở về trạng thái gốc (dạng XML bình thường).
## Chỉnh sửa file mã hóa trực tiếp
Nếu muốn chỉnh sửa nội dung đã mã hóa mà không giải mã toàn bộ file: `ansible-vault edit /backups/pfsense-config-pfSense.xml`
## Tự động dùng vault password (nếu cần automation)
- Tạo file chứa mật khẩu vault, ví dụ:
    ```
    echo "myvaultpassword" > ~/.vault_pass.txt
    chmod 600 ~/.vault_pass.txt
    ```
- Sau đó chạy Ansible với tham số --vault-password-file: `ansible-playbook playbooks/backup_pfsense.yml --vault-password-file ~/.vault_pass.txt`
- Hoặc cấu hình sẵn trong ansible.cfg:
    ```
    [defaults]
    vault_password_file = ~/.vault_pass.txt
    ```
## Mã hóa một biến hoặc chuỗi
- Câu lệnh: 
`ansible-vault encrypt_string 'my_secret_password' --name 'pfsense_admin_pass'`
# Cấu hình 
## Playbook
### Switches_backup.yml
| Bước     | Mô tả                                                    | Biến/Thao tác                                              |
| -------- | -------------------------------------------------------- | ---------------------------------------------------------- |
| **0**    | Tạo biến thời gian hiện tại                              | `timestamp`                                                |
| **1**    | Tạo thư mục chính cho từng thiết bị                      | `base_dir = /backups/switches/{{ inventory_hostname }}`    |
| **2a**   | Tạo tên thư mục phụ theo thời gian + tên thiết bị        | `backup_subdir = {{ timestamp }}-{{ inventory_hostname }}` |
| **2b.1** | Gộp thành đường dẫn đầy đủ để lưu                        | `backup_dir = {{ base_dir }}/{{ backup_subdir }}`          |
| **2b.2** | Tạo đường dẫn file cấu hình                              | `config_file = {{ backup_dir }}/run-config.txt`            |
| **2b.3** | Tạo đường dẫn file nén                                   | `archive_file = {{ backup_dir }}/backup-run.tar.gz`        |
| **3**    | Kết nối đến thiết bị, lấy cấu hình `show running-config` | `ios_command`                                              |
| **4**    | Tạo thư mục backup trên localhost                        | `file`                                                     |
| **5**    | Ghi nội dung cấu hình vào `run-config.txt`               | `copy`                                                     |
| **6**    | Tạo file nén `backup-run.tar.gz` từ file txt             | `tar`                                                      |
| **7**    | Hiển thị thông báo backup thành công                     | `debug`                                                    |
---
    ---
    - name: Backup config from switches (clean structure)
    hosts: switches
    gather_facts: no
    become: false

    tasks:

        - name: Step 0 - Set current timestamp
        set_fact:
            timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"

        - name: Step 1 - Set base backup directory
        set_fact:
            base_dir: "/backups/switches/{{ inventory_hostname }}"

        - name: Step 2a - Set backup subdirectory name
        set_fact:
            backup_subdir: "{{ timestamp }}-{{ inventory_hostname }}"

        - name: Step 2b.1 - Set backup directory path
        set_fact:
            backup_dir: "{{ base_dir }}/{{ backup_subdir }}"

        - name: Step 2b.2 - Set config file path
        set_fact:
            config_file: "{{ backup_dir }}/run-config.txt"

        - name: Step 2b.3 - Set archive file path
        set_fact:
            archive_file: "{{ backup_dir }}/backup-run.tar.gz"

        - name: Get running config from Cisco switch
        ios_command:
            commands: show running-config
        register: config_output

        - name: Create backup directory
        delegate_to: localhost
        file:
            path: "{{ backup_dir }}"
            state: directory
            mode: '0755'

        - name: Save running config to file
        delegate_to: localhost
        copy:
            content: "{{ config_output.stdout[0] }}"
            dest: "{{ config_file }}"

        - name: Archive the run-config.txt
        delegate_to: localhost
        command: >
            tar -czf {{ archive_file }} -C {{ backup_dir }} run-config.txt

        - name: Show archive file location
        delegate_to: localhost
        debug:
            msg: "✅ Switch '{{ inventory_hostname }}' đã backup xong tại {{ archive_file }}"

### Pfsense_backup.yml
```
---
- name: Backup pfSense configuration
  hosts: pfsense
  gather_facts: no
  become: false

  tasks:
    - name: Step 0 - Set backup timestamp
      set_fact:
        backup_timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"

    - name: Step 1 - Set backup paths (using timestamp fact)
      set_fact:
        paths:
          backup_dir: "/backups/pfsense/{{ inventory_hostname }}/{{ backup_timestamp }}"
          backup_file: "/backups/pfsense/{{ inventory_hostname }}/{{ backup_timestamp }}/pfsense-config.xml"
          archive_file: "/backups/pfsense/{{ inventory_hostname }}/{{ backup_timestamp }}/{{ inventory_hostname }}.tar.gz"

    - name: Step 2 - Ensure backup directory exists
      delegate_to: localhost
      file:
        path: "{{ paths.backup_dir }}"
        state: directory
        mode: '0755'

    - name: Step 3 - Fetch pfSense config.xml
      shell: cat /cf/conf/config.xml
      register: config_data

    - name: Step 4 - Save config to local file
      delegate_to: localhost
      copy:
        content: "{{ config_data.stdout }}"
        dest: "{{ paths.backup_file }}"

    - name: Step 5 - Archive backup file
      delegate_to: localhost
      archive:
        path: "{{ paths.backup_file }}"
        dest: "{{ paths.archive_file }}"
        format: gz

    - name: ✅ Done - Show archive file location
      delegate_to: localhost
      debug:
        msg: "✅ pfSense '{{ inventory_hostname }}' đã backup xong tại {{ paths.archive_file }}"
```
### Script menu.sh
```
#!/bin/bash

WORK_DIR="/automation/network-automation"
INVENTORY_FILE="$WORK_DIR/inventory/hosts"

if [[ "$1" == "auto" ]]; then
  choice=3
else
  clear
  echo "?? SELECT SYSTEM TO BACKUP:"
  echo "1 - Backup SWITCH"
  echo "2 - Backup pfSENSE"
  echo "3 - Backup ALL"
  echo "0 - Exit"
  echo "------------------------------------"
  read -p "Enter your choice: " choice
fi

# Backup pfSense theo host
backup_pfsense_host() {
  echo "?? Detecting pfSense hosts from inventory..."
  mapfile -t PFSENSE_HOSTS < <(awk '/^\[pfsense\]/ {f=1; next} /^\[/ {f=0} f && NF {print $1}' "$INVENTORY_FILE")

  if [ ${#PFSENSE_HOSTS[@]} -eq 0 ]; then
    echo "? No pfSense hosts found in inventory."
    exit 1
  fi

  if [[ "$1" == "auto" ]]; then
    for host in "${PFSENSE_HOSTS[@]}"; do
      echo "?? Auto-backup pfSense host: $host"
      ansible-playbook "$WORK_DIR/playbooks/pfsense_backup.yml" -i "$INVENTORY_FILE" -l "$host"
    done
  else
    echo "Available pfSense hosts:"
    for i in "${!PFSENSE_HOSTS[@]}"; do
      echo "$((i+1)) - ${PFSENSE_HOSTS[$i]}"
    done
    echo "$(( ${#PFSENSE_HOSTS[@]} + 1 )) - ALL"

    read -p "Select a host to back up (1-${#PFSENSE_HOSTS[@]} or ALL): " host_index

    if [[ "$host_index" =~ ^[0-9]+$ ]] && [ "$host_index" -ge 1 ] && [ "$host_index" -le "${#PFSENSE_HOSTS[@]}" ]; then
      selected_host="${PFSENSE_HOSTS[$((host_index-1))]}"
      echo "?? Backing up pfSense host: $selected_host"
      ansible-playbook "$WORK_DIR/playbooks/pfsense_backup.yml" -i "$INVENTORY_FILE" -l "$selected_host"
    elif [[ "$host_index" -eq $(( ${#PFSENSE_HOSTS[@]} + 1 )) ]]; then
      for host in "${PFSENSE_HOSTS[@]}"; do
        echo "?? Backing up pfSense host: $host"
        ansible-playbook "$WORK_DIR/playbooks/pfsense_backup.yml" -i "$INVENTORY_FILE" -l "$host"
      done
    else
      echo "? Invalid selection."
      exit 1
    fi
  fi
}

# Backup switch theo host
backup_switch_host() {
  echo "?? Detecting SWITCH hosts from inventory..."
  mapfile -t SWITCH_HOSTS < <(awk '/^\[switches\]/ {f=1; next} /^\[/ {f=0} f && NF {print $1}' "$INVENTORY_FILE")

  if [ ${#SWITCH_HOSTS[@]} -eq 0 ]; then
    echo "? No switch hosts found in inventory."
    exit 1
  fi

  echo "Available switch hosts:"
  for i in "${!SWITCH_HOSTS[@]}"; do
    echo "$((i+1)) - ${SWITCH_HOSTS[$i]}"
  done
  echo "$(( ${#SWITCH_HOSTS[@]} + 1 )) - ALL"

  read -p "Select a host to back up (1-${#SWITCH_HOSTS[@]} or ALL): " host_index

  if [[ "$host_index" =~ ^[0-9]+$ ]] && [ "$host_index" -ge 1 ] && [ "$host_index" -le "${#SWITCH_HOSTS[@]}" ]; then
    selected_host="${SWITCH_HOSTS[$((host_index-1))]}"
    echo "?? Backing up SWITCH host: $selected_host"
    ansible-playbook "$WORK_DIR/playbooks/switches_backups.yml" -i "$INVENTORY_FILE" -l "$selected_host"
  elif [[ "$host_index" -eq $(( ${#SWITCH_HOSTS[@]} + 1 )) ]]; then
    for host in "${SWITCH_HOSTS[@]}"; do
      echo "?? Backing up SWITCH host: $host"
      ansible-playbook "$WORK_DIR/playbooks/switches_backups.yml" -i "$INVENTORY_FILE" -l "$host"
    done
  else
    echo "? Invalid selection."
    exit 1
  fi
}

# Main logic
case $choice in
  1)
    backup_switch_host
    ;;
  2)
    backup_pfsense_host
    ;;
  3)
    echo "?? Running full backup (SWITCH + pfSENSE)..."
    for group in switches pfsense; do
      mapfile -t hosts < <(awk "/^\[$group\]/ {f=1; next} /^\[/ {f=0} f && NF {print \$1}" "$INVENTORY_FILE")
      for host in "${hosts[@]}"; do
        if [ "$group" == "switches" ]; then
          echo "?? Backing up SWITCH host: $host"
          ansible-playbook "$WORK_DIR/playbooks/switches_backups.yml" -i "$INVENTORY_FILE" -l "$host"
        else
          echo "?? Backing up pfSense host: $host"
          ansible-playbook "$WORK_DIR/playbooks/pfsense_backup.yml" -i "$INVENTORY_FILE" -l "$host"
        fi
      done
    done
    ;;
  0)
    echo "?? Exiting..."
    exit 0
    ;;
  *)
    echo "? Invalid choice. Please select 0, 1, 2, or 3."
    exit 1
    ;;
esac
```
## Tự động hóa lịch backup định kỳ (cronjob)
```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 2  * * * /automation/network-automation/menu.sh auto >> /var/log/backups_auto/devices_backup.log 2>&1
```