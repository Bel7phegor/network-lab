import requests
from fpdf import FPDF
from datetime import datetime, timedelta
import os
import traceback
import time

# ================= SYSTEM CONFIGURATION =================
GRAFANA_URL = "http://192.168.254.254:3000"
PROMETHEUS_URL = "http://192.168.254.254:9090"
GRAFANA_TOKEN = "Bearer glsa_fdLTI8mLbIBPHXGhhHiziE5VScbSTvsW_5cc1fbc1" 
TELEGRAM_TOKEN = "7926001781:AAGyByulcRakN7riHRdw1AOwGazYztXpeaI"            
CHAT_ID = "-4638379865"                                
DASHBOARD_UID = "backup-automation-table-view" 

PANELS = [
    {"id": 2, "name": "7-Day Backup Timeline", "w": 1000, "h": 400, "pdf_w": 180},   
    {"id": 4, "name": "Weekly Statistics", "w": 1000, "h": 300, "pdf_w": 140},       
]

# ================= HELPER FUNCTIONS =================

def get_weekly_metrics():
    """
    Lấy thống kê và danh sách lỗi chính xác từ Prometheus
    """
    end_time = datetime.now()
    start_time = end_time - timedelta(days=7)
    
    start_ts = start_time.timestamp()
    end_ts = end_time.timestamp()
    
    stats = {
        "total_checks": 0,
        "total_failures": 0,
        "reliability": 100.0,
        "failure_events": []
    }
    
    # Dùng set để lọc trùng lặp các sự kiện lỗi giống hệt nhau
    seen_events = set()

    try:
        # 1. Query Range: Lấy dữ liệu lịch sử
        query = 'auto_backup_status == 1'
        response = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query_range", 
            params={
                'query': query,
                'start': start_ts,
                'end': end_ts,
                'step': '24h' 
            },
            timeout=10
        )
        data = response.json()
        
        if data['status'] == 'success':
            for result in data['data']['result']:
                metric_info = result['metric']
                host = metric_info.get('host', 'Unknown')
                error_msg = metric_info.get('error', 'Unknown Error')
                
                # --- QUAN TRỌNG: Lấy label timestamp từ metrics ---
                # Đây là giá trị "2025-12-27..." mà bạn muốn
                real_timestamp = metric_info.get('timestamp', None)

                # Duyệt qua các điểm dữ liệu để đếm số lần fail
                for timestamp, value in result['values']:
                    if int(value) == 1:
                        stats["total_failures"] += 1
                        
                        # Xử lý ngày hiển thị
                        display_date = ""
                        if real_timestamp:
                            display_date = real_timestamp # Lấy từ label (Chính xác nhất)
                        else:
                            # Fallback nếu không có label timestamp
                            display_date = datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M')

                        # Tạo ID duy nhất cho sự kiện để không in lại nhiều lần
                        event_id = f"{host}_{display_date}"
                        
                        if event_id not in seen_events:
                            stats["failure_events"].append({
                                "date": display_date,
                                "host": host,
                                "error": error_msg
                            })
                            seen_events.add(event_id)

        # 2. Tính toán tổng quan (Reliability)
        count_query = 'count(auto_backup_status)'
        res_count = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': count_query})
        data_count = res_count.json()
        total_devices = 0
        if data_count['status'] == 'success' and len(data_count['data']['result']) > 0:
             total_devices = int(data_count['data']['result'][0]['value'][1])
        
        stats["total_checks"] = total_devices * 7
        
        if stats["total_checks"] > 0:
            success_count = stats["total_checks"] - stats["total_failures"]
            stats["reliability"] = (success_count / stats["total_checks"]) * 100
            if stats["reliability"] < 0: stats["reliability"] = 0

    except Exception:
        traceback.print_exc()
        
    # Sắp xếp danh sách lỗi theo thời gian (mới nhất lên đầu)
    stats["failure_events"].sort(key=lambda x: x['date'], reverse=True)
    return stats

def get_panel_image_weekly(panel_id, width, height, filename):
    url = f"{GRAFANA_URL}/render/d-solo/{DASHBOARD_UID}/dashboard?orgId=1&panelId={panel_id}&width={width}&height={height}&tz=Asia%2FHo_Chi_Minh&from=now-7d&to=now"
    headers = {"Authorization": GRAFANA_TOKEN}
    try:
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            with open(filename, 'wb') as f:
                f.write(response.content)
            return True
    except Exception:
        pass
    return False

# ================= PDF CLASS =================

class PDF(FPDF):
    def header(self):
        self.set_font('Arial', 'B', 10)
        self.cell(0, 10, 'Weekly Network Audit', 0, 0, 'R')
        self.ln(10)
    
    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')

def create_weekly_report():
    print("--- 1. Analyzing Weekly Data (7 Days) ---")
    stats = get_weekly_metrics()
    
    start_date = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    end_date = datetime.now().strftime("%Y-%m-%d")

    pdf = PDF()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()
    
    # --- TITLE ---
    pdf.set_font("Arial", 'B', 22)
    pdf.cell(0, 10, txt="WEEKLY BACKUP REPORT", ln=1, align='C')
    pdf.set_font("Arial", 'I', 11)
    pdf.cell(0, 10, txt=f"Period: {start_date} to {end_date}", ln=1, align='C')
    pdf.ln(10)

    # --- SECTION 1: SUMMARY ---
    pdf.set_fill_color(230, 240, 255)
    pdf.rect(10, pdf.get_y(), 190, 40, 'F')
    
    pdf.set_xy(15, pdf.get_y() + 5)
    pdf.set_font("Arial", 'B', 14)
    pdf.cell(0, 10, txt="1. PERFORMANCE SUMMARY", ln=1)
    
    rel_color = (0, 128, 0) if stats["reliability"] >= 90 else (200, 0, 0)
    
    pdf.set_x(20)
    pdf.set_font("Arial", '', 12)
    pdf.cell(50, 8, txt="System Reliability:")
    pdf.set_font("Arial", 'B', 12)
    pdf.set_text_color(*rel_color)
    pdf.cell(0, 8, txt=f"{stats['reliability']:.1f}%", ln=1)
    
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Arial", '', 11)
    pdf.set_x(20)
    pdf.cell(90, 8, txt=f"- Est. Total Backups: {stats['total_checks']}")
    pdf.cell(90, 8, txt=f"- Total Failures: {stats['total_failures']}")
    pdf.ln(15)

    # --- SECTION 2: FAILURE LOG ---
    pdf.set_font("Arial", 'B', 14)
    pdf.cell(0, 10, txt="2. FAILURE INCIDENT LOG", ln=1)
    
    if len(stats["failure_events"]) > 0:
        # Table Header - Điều chỉnh độ rộng cột
        pdf.set_fill_color(200, 200, 200)
        pdf.set_font("Arial", 'B', 10)
        # Cột Date mở rộng lên 45 để chứa chuỗi dài
        pdf.cell(45, 8, "Last Attempt", 1, 0, 'C', 1) 
        pdf.cell(35, 8, "Device", 1, 0, 'C', 1)
        pdf.cell(110, 8, "Error Reason", 1, 1, 'C', 1)
        
        pdf.set_font("Arial", '', 8) # Font nhỏ hơn chút để vừa log
        for event in stats["failure_events"]:
            pdf.cell(45, 8, str(event["date"]), 1, 0, 'C')
            pdf.cell(35, 8, str(event["host"]), 1, 0, 'C')
            
            # Cắt ngắn lỗi nếu quá dài
            err_msg = str(event["error"])
            short_err = (err_msg[:60] + '..') if len(err_msg) > 60 else err_msg
            pdf.cell(110, 8, short_err, 1, 1, 'L')
    else:
        pdf.set_text_color(0, 128, 0)
        pdf.cell(0, 8, txt="Excellent! No backup failures recorded in the last 7 days.", ln=1)
        pdf.set_text_color(0, 0, 0)

    pdf.ln(10)

    # --- SECTION 3: CHARTS ---
    pdf.set_font("Arial", 'B', 14)
    pdf.cell(0, 10, txt="3. 7-DAY VISUALIZATION", ln=1)
    pdf.ln(2)

    print("--- 2. Downloading Weekly Charts ---")
    fig_counter = 1
    for panel in PANELS:
        img_name = f"weekly_temp_{panel['id']}.png"
        
        if get_panel_image_weekly(panel['id'], panel['w'], panel['h'], img_name):
            img_h_mm = (panel['h'] / panel['w']) * panel['pdf_w']
            
            if pdf.get_y() + img_h_mm + 15 > 270: 
                pdf.add_page()
            
            x_pos = (210 - panel['pdf_w']) / 2
            pdf.image(img_name, x=x_pos, w=panel['pdf_w'])
            
            pdf.ln(2)
            pdf.set_font("Arial", 'I', 9)
            pdf.cell(0, 5, txt=f"Figure {fig_counter}: {panel['name']}", ln=1, align='C')
            pdf.ln(8)
            fig_counter += 1
            os.remove(img_name)

    filename = f"Weekly_Report_{datetime.now().strftime('%Y%m%d')}.pdf"
    pdf.output(filename)
    return filename

# ================= TELEGRAM =================
def send_telegram(pdf_file):
    if not pdf_file: return
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendDocument"
    caption_text = (
        "📅 *WEEKLY NETWORK REPORT*\n"
        f"⏱ Period: Last 7 Days\n"
        "🔎 Incident timestamps are now accurate."
    )
    files = {'document': open(pdf_file, 'rb')}
    data = {'chat_id': CHAT_ID, 'caption': caption_text, 'parse_mode': 'Markdown'}
    try:
        requests.post(url, files=files, data=data, timeout=30)
        print("✅ WEEKLY REPORT SENT!")
    except Exception as e:
        print(f"❌ Telegram Error: {e}")

if __name__ == "__main__":
    try:
        f_name = create_weekly_report()
        if f_name:
            send_telegram(f_name)
            if os.path.exists(f_name):
                os.remove(f_name)
                print("--- Cleanup Complete ---")
    except Exception as e:
        traceback.print_exc()
