# NetDevOps: Enterprise Network Infrastructure & Automation Lab

![Status](https://img.shields.io/badge/Status-Active-success?style=flat-square)
![Architecture](https://img.shields.io/badge/Architecture-3--Tier%20%7C%20Multi--Site-blue?style=flat-square)
![Tech Stack](https://img.shields.io/badge/Tech-Ansible%20%7C%20Prometheus%20%7C%20Loki%20%7C%20Teleport-orange?style=flat-square)

## 📖 Giới thiệu (Overview)

Dự án mô phỏng hệ thống mạng doanh nghiệp quy mô đa chi nhánh (Multi-site), kết hợp quy trình vận hành tự động hóa (**NetDevOps**). Hệ thống giải quyết bài toán quản trị tập trung, đảm bảo tính sẵn sàng cao (High Availability) và khả năng giám sát toàn diện từ hạ tầng mạng đến ứng dụng.

### 🎯 Mục tiêu chính

* **Hạ tầng mạng:** Thiết kế mạng phân lớp, định tuyến động OSPF, dự phòng Gateway với Cisco HSRP.

* **Tự động hóa:** Loại bỏ cấu hình thủ công, tự động sao lưu và triển khai dịch vụ bằng Ansible.

* **Giám sát:** Thu thập metrics/logs tập trung, cảnh báo tức thời qua Telegram.

* **Bảo mật:** Ứng dụng Zero Trust Access (Teleport), IDS Snort và VPN IPsec Site-to-Site.

## 🏗️ Kiến trúc & Quy hoạch (Architecture & Planning)

### 1. Topology & Connectivity

Hệ thống vận hành trên môi trường lai (Hybrid): **GNS3** (Network) kết hợp **VMware** (Server).

* **Gateway Layer:** PFSense đảm nhiệm Firewall, NAT, VPN IPsec kết nối các Site, và Snort IDS.

* **Core/Distribution Layer:** Cặp Switch Cisco L3 chạy **HSRP** (Hot Standby Router Protocol) để chia tải và dự phòng Gateway cho người dùng.

* **DMZ Zone:** Vùng cách ly chứa các Server quan trọng (Monitoring, Automation, App), được bảo vệ bởi Firewall Rules chặt chẽ.

### 2. Quy hoạch IP & VLAN (IP Allocation)

Hệ thống sử dụng dải IP Class C (`192.168.x.x`) để quy hoạch theo cấu trúc `192.168.VlanID.Host`, đảm bảo khả năng mở rộng cho doanh nghiệp đa chi nhánh.

**Site quy hoạch: Đà Nẵng (Site ID: 1)**

| VLAN ID | Subnet | Vai trò (Role) | Ghi chú | 
 | ----- | ----- | ----- | ----- | 
| **99** | `192.168.99.0/24` | **Management** | Dải mạng quản trị thiết bị & Teleport (Isolated) | 
| **10** | `192.168.10.0/24` | Department A | Phòng Admin / IT Team | 
| **20** | `192.168.20.0/24` | Department B | Phòng Nhân sự / Staff | 
| **30** | `192.168.30.0/24` | Department C | Server Farm (Web, App, DB) | 
| **40** | `192.168.40.0/24` | Guest / IoT | Mạng khách (Internet Only) | 
| **254** | `192.168.254.0/24` | **DMZ Services** | Monitor/logs/alert
> **Cấu hình Switch Core:**
>
> * **HSRP Group 10, 30:** Switch Core 1 làm Active (Ưu tiên traffic Admin/Server).
>
> * **HSRP Group 20, 40:** Switch Core 2 làm Active (Ưu tiên traffic Staff/Guest).
>
> * **Routing:** Sử dụng **OSPF** để quảng bá các dải mạng nội bộ và kết nối sang vùng DMZ.

## 🛠️ Công nghệ sử dụng (Tech Stack)

| Lĩnh vực | Công nghệ | Chi tiết triển khai | 
 | ----- | ----- | ----- | 
| **Infrastructure** | **PFSense** | Firewall, HAProxy, Snort IDS, VPN IPsec | 
|  | **Cisco IOS** | VLAN, Trunking, Etherchannel, HSRP, OSPF | 
| **Automation** | **Ansible** | Quản lý cấu hình (IaC), Auto Backup, Service Provisioning | 
|  | **Bash** | Scripting, Menu Automation | 
| **Observability** | **Prometheus** | Thu thập Metrics (CPU, RAM, Traffic) | 
|  | **Grafana** | Hiển thị Dashboard trực quan | 
|  | **Loki & Promtail** | Thu thập và truy vấn Log tập trung | 
|  | **Alertmanager** | Gửi cảnh báo qua Telegram | 
| **Security** | **Teleport** | Quản lý truy cập SSH/Web tập trung (Audit & Session Recording) | 


## 📂 Cấu trúc Thư mục (Directory Structure)

```plaintext
.
├── Alertmanager            # Cấu hình cảnh báo
│   └── alertmanager
│       ├── templates       # Mẫu tin nhắn Telegram
│       └── alertmanager.yml
├── Automation              # Trung tâm điều khiển Ansible
│   └── automation
│       ├── network-automation
│       │   ├── inventory   # Danh sách thiết bị (Hosts)
│       │   └── playbooks   # Các kịch bản tự động hóa
│       │       ├── backup  # Backup PFSense & Switch
│       │       ├── restore # Khôi phục cấu hình
│       │       ├── nginx   # Quản lý Nginx Service
│       │       └── teleport # Triển khai Teleport Agent
│       └── script          # Scripts (auto_backup.sh, menu.sh)
├── Grafana                 # Dashboards & Provisioning
├── Prometheus              # Cấu hình giám sát Metrics
│   ├── prometheus
│   │   ├── rules           # Luật cảnh báo (Alert Rules)
│   │   └── snmp.yml        # Cấu hình OID giám sát thiết bị mạng
├── PFSense                 # File cấu hình XML
└── Switch                  # Startup-configs
```

## 🚀 Tính năng Tự động hóa (Automation Workflows)

### 1. Auto Backup Strategy (Disaster Recovery)

Hệ thống đảm bảo an toàn dữ liệu cấu hình thông qua quy trình sao lưu tự động.

* **Lịch trình:** Cronjob chạy lúc **02:00 AM** hàng ngày.

* **Đối tượng:** File cấu hình Cisco Switch (`running-config`) và PFSense (`config.xml`).

* **Cơ chế:** Script tự động SSH vào thiết bị lấy file -> Lưu trữ có Versioning -> Bắn metric trạng thái (Success/Fail) về Prometheus để giám sát.

### 2. Infrastructure Provisioning

Sử dụng Ansible Playbooks để triển khai nhanh:

* **Nginx:** Tự động cài đặt Web Server, cấu hình Virtual Host và tích hợp Exporter.

* **Teleport Agent:** Tự động join một node mới (VD: Server mới mua) vào cụm quản trị Teleport chỉ với 1 click script.

## 👁️ Hệ thống Giám sát (Monitoring Stack)

Hệ thống giám sát đặt tại vùng DMZ (`VLAN 30`), triển khai bằng **Docker Compose**:

1. **Network Monitoring:**

   * Giám sát băng thông, trạng thái cổng (Up/Down), lỗi CRC trên Switch/Router qua giao thức **SNMP**.

2. **Server Health:**

   * Theo dõi CPU, RAM, Disk Space của các máy chủ qua **Node Exporter**.

3. **Centralized Logging (PLG Stack):**

   * **Promtail** nhận Syslog (UDP 514) từ thiết bị mạng và đọc log file từ Server.

   * **Loki** lưu trữ và đánh chỉ mục log.

   * **Grafana** cho phép search/filter log để troubleshooting.

4. **Alerting:**

   * Tự động gửi tin nhắn Telegram khi: Backup thất bại, Traffic cao bất thường, hoặc thiết bị mất kết nối.

## 🔐 Bảo mật (Security Implementation)

- **Snort IDS:** Phát hiện và ngăn chặn xâm nhập mạng tại Gateway PFSense.
- **Teleport Access Plane:**
    - Thay thế SSH Password truyền thống bằng Certificate-based authentication.
    - Truy cập tập trung qua Web UI hoặc CLI (`tsh`).
    - Ghi lại phiên làm việc (Session Recording) phục vụ Audit.
- **DMZ Segmentation:** Phân vùng mạng riêng biệt cho các Server quan trọng, cách ly với mạng User.
- **IPsec VPN:** Mã hóa đường truyền kết nối giữa Site Đà Nẵng và Site Hồ Chí Minh.

---

## 📝 Hướng dẫn chạy (Quick Start)

### 1. Khởi chạy Monitoring Stack
```bash
cd Monitoring
docker-compose up -d
# Truy cập Grafana tại: http://<IP-Monitoring>:3000
# User/Pass mặc định: admin/admin
```

### 2. Chạy Backup thủ công (Ad-hoc)
```bash
cd Automation/automation/network-automation

# Backup toàn bộ Switch
ansible-playbook playbooks/backup/switch_backup.yml

# Backup PFSense
ansible-playbook playbooks/backup/pfsense_backup.yml
```

### 3. Sử dụng Menu quản trị
```bash
./Automation/automation/script/nginx-menu.sh
# Chọn các option: 1. Install, 2. Remove, 3. Check Status...
```

---

## 👨‍💻 Author
**[Tên của bạn]** - Network & DevOps Engineer