import requests
from fpdf import FPDF
from datetime import datetime
import os
import traceback
import time

GRAFANA_URL = "http://192.168.254.254:3000"
PROMETHEUS_URL = "http://192.168.254.254:9090"
GRAFANA_TOKEN = "Bearer glsa_fdLTI8mLbIBPHXGhhHiziE5VScbSTvsW_5cc1fbc1" 
TELEGRAM_TOKEN = "8245121645:AAEZjy6vccw3dQOgVud3hWPiF9OqTF9JtfE"
CHAT_ID = "-5105157102 "                                
DASHBOARD_UID = "7qKD6I1Wk" 

PANELS_TEMPLATE = [
    {"id": 21, "name": "Traffic Trend (In/Out)", "w": 1000, "h": 500, "pdf_w": 190},
    {"id": 26, "name": "Interface Details Table", "w": 1300, "h": 800, "pdf_w": 190}
]


def get_snmp_jobs():
    
    jobs = []
    try:
        query = "group(ifHCInOctets) by (job)"
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query}, timeout=10)
        data = response.json()
        
        if data['status'] == 'success':
            for result in data['data']['result']:
                job_name = result['metric'].get('job')
                if job_name:
                    jobs.append(job_name)
    except Exception:
        traceback.print_exc()
    return jobs

def get_job_metrics(job_name):
    stats = {
        "total_in_gb": 0.0,
        "total_out_gb": 0.0,
        "max_speed_in": 0.0,
        "max_speed_out": 0.0
    }
    try:
        # 1. Total Download (GB)
        q_in = f'sum(delta(ifHCInOctets{{job="{job_name}"}}[24h])) / 1024 / 1024 / 1024'
        stats["total_in_gb"] = get_scalar_value(q_in)

        # 2. Total Upload (GB)
        q_out = f'sum(delta(ifHCOutOctets{{job="{job_name}"}}[24h])) / 1024 / 1024 / 1024'
        stats["total_out_gb"] = get_scalar_value(q_out)

        # 3. Max Speed (Mbps)
        q_max_in = f'max(max_over_time(rate(ifHCInOctets{{job="{job_name}"}}[5m])[24h:5m])) * 8 / 1000 / 1000'
        stats["max_speed_in"] = get_scalar_value(q_max_in)
        
        q_max_out = f'max(max_over_time(rate(ifHCOutOctets{{job="{job_name}"}}[5m])[24h:5m])) * 8 / 1000 / 1000'
        stats["max_speed_out"] = get_scalar_value(q_max_out)

    except Exception:
        traceback.print_exc()
        
    return stats

def get_down_interfaces(job_name):
    """
    Lấy danh sách cổng DOWN (ifOperStatus == 2)
    """
    down_ports = []
    try:
        query = f'ifOperStatus{{job="{job_name}", ifName!~"lo.*|pf.*"}} == 2'
        
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query}, timeout=10)
        data = response.json()
        
        if data['status'] == 'success':
            for result in data['data']['result']:
                metric = result['metric']
                port_name = metric.get('ifName', 'Unknown')
                port_alias = metric.get('ifAlias', '') 
                
                down_ports.append({
                    "name": port_name,
                    "alias": port_alias
                })
    except Exception:
        traceback.print_exc()
    return down_ports

def get_scalar_value(query):
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query}, timeout=10)
        data = response.json()
        if data['status'] == 'success' and len(data['data']['result']) > 0:
            return float(data['data']['result'][0]['value'][1])
    except:
        pass
    return 0.0

def get_panel_image_with_var(panel_id, width, height, job_name, filename):
    url = (f"{GRAFANA_URL}/render/d-solo/{DASHBOARD_UID}/dashboard"
           f"?orgId=1&panelId={panel_id}&width={width}&height={height}"
           f"&tz=Asia%2FHo_Chi_Minh&from=now-24h&to=now&var-Job={job_name}")
    
    headers = {"Authorization": GRAFANA_TOKEN}
    try:
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            with open(filename, 'wb') as f:
                f.write(response.content)
            return True
        else:
            print(f"[ERROR] Grafana render failed for {job_name}: {response.status_code}")
    except Exception:
        pass
    return False

# ================= PDF CLASS =================

class PDF(FPDF):
    def header(self):
        self.set_font('Arial', 'B', 10)
        self.cell(0, 10, 'Network Traffic Audit System', 0, 0, 'R')
        self.ln(10)
    
    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')

def create_traffic_report():
    print("--- 1. Scanning SNMP Devices ---")
    jobs = get_snmp_jobs()
    print(f"   Found SNMP jobs: {jobs}")
    
    if not jobs:
        print("No SNMP devices found! Check Prometheus Exporter.")
        return None

    today_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    pdf = PDF()
    pdf.set_auto_page_break(auto=True, margin=20)
    
    # --- COVER PAGE ---
    pdf.add_page()
    pdf.set_font("Arial", 'B', 24)
    pdf.cell(0, 60, txt="", ln=1)
    pdf.cell(0, 20, txt="DAILY TRAFFIC REPORT", ln=1, align='C')
    pdf.set_font("Arial", 'I', 14)
    pdf.cell(0, 10, txt=f"Generated: {today_str}", ln=1, align='C')
    pdf.cell(0, 10, txt=f"Devices Monitored: {len(jobs)}", ln=1, align='C')
    pdf.ln(20)

    # --- PROCESS EACH JOB ---
    for job in jobs:
        print(f"--- Processing: {job} ---")
        metrics = get_job_metrics(job)
        down_interfaces = get_down_interfaces(job)
        
        pdf.add_page()
        
        # Job Title
        pdf.set_font("Arial", 'B', 18)
        pdf.cell(0, 10, txt=f"DEVICE: {job.upper()}", ln=1, align='L')
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(5)

        # 1. Summary Box
        pdf.set_fill_color(245, 245, 245)
        pdf.rect(10, pdf.get_y(), 190, 35, 'F')
        
        pdf.set_y(pdf.get_y() + 5)
        pdf.set_font("Arial", 'B', 12)
        pdf.set_x(15)
        pdf.cell(0, 8, txt="24-Hour Statistics:", ln=1)
        
        pdf.set_font("Arial", '', 11)
        pdf.set_x(20)
        col_1_x = 20
        col_2_x = 110
        y_pos = pdf.get_y()
        
        pdf.set_xy(col_1_x, y_pos)
        pdf.cell(80, 8, txt=f"- Total Download: {metrics['total_in_gb']:.2f} GB")
        pdf.set_xy(col_2_x, y_pos)
        pdf.cell(80, 8, txt=f"- Peak In Speed: {metrics['max_speed_in']:.2f} Mbps")
        
        pdf.ln(8)
        y_pos = pdf.get_y()
        pdf.set_xy(col_1_x, y_pos)
        pdf.cell(80, 8, txt=f"- Total Upload: {metrics['total_out_gb']:.2f} GB")
        pdf.set_xy(col_2_x, y_pos)
        pdf.cell(80, 8, txt=f"- Peak Out Speed: {metrics['max_speed_out']:.2f} Mbps")
        
        pdf.ln(15)

        # 2. DOWN INTERFACES ALERT
        pdf.set_font("Arial", 'B', 12)
        pdf.cell(0, 10, txt="Interface Status Alerts (Currently DOWN)", ln=1)
        
        if len(down_interfaces) > 0:
            pdf.set_font("Arial", 'B', 10)
            pdf.set_fill_color(255, 200, 200) # Light Red
            pdf.cell(60, 8, "Interface Name", 1, 0, 'C', 1)
            pdf.cell(130, 8, "Alias / Description", 1, 1, 'C', 1)
            
            pdf.set_font("Arial", '', 10)
            pdf.set_text_color(200, 0, 0)
            for port in down_interfaces:
                pdf.cell(60, 8, port['name'], 1, 0, 'C')
                # Xử lý nếu alias quá dài thì cắt bớt
                alias_txt = port['alias'] if len(port['alias']) < 60 else port['alias'][:57] + "..."
                pdf.cell(130, 8, alias_txt, 1, 1, 'L')
            pdf.set_text_color(0, 0, 0)
        else:
            pdf.set_font("Arial", 'I', 10)
            pdf.set_text_color(0, 128, 0)
            pdf.cell(0, 8, txt="All monitored interfaces are UP.", ln=1)
            pdf.set_text_color(0, 0, 0)

        pdf.ln(10)

        # 3. Visualizations
        pdf.set_font("Arial", 'B', 14)
        pdf.cell(0, 10, txt="Visualizations", ln=1)
        
        for panel in PANELS_TEMPLATE:
            img_name = f"traffic_{job}_{panel['id']}.png"
            
            if get_panel_image_with_var(panel['id'], panel['w'], panel['h'], job, img_name):
                img_h_mm = (panel['h'] / panel['w']) * panel['pdf_w']
                
                # Check page break
                if pdf.get_y() + img_h_mm + 15 > 270:
                    pdf.add_page()
                
                x_pos = (210 - panel['pdf_w']) / 2
                pdf.image(img_name, x=x_pos, w=panel['pdf_w'])
                
                pdf.ln(2)
                pdf.set_font("Arial", 'I', 9)
                pdf.cell(0, 5, txt=f"{panel['name']} ({job})", ln=1, align='C')
                pdf.ln(8)
                
                os.remove(img_name)
            else:
                pdf.set_text_color(200, 0, 0)
                pdf.cell(0, 10, txt=f"[Error loading Panel {panel['id']}]", ln=1)
                pdf.set_text_color(0, 0, 0)

    filename = f"Traffic_Report_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf"
    pdf.output(filename)
    return filename

# ================= TELEGRAM =================
def send_telegram(pdf_file):
    if not pdf_file: return
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendDocument"
    caption_text = (
        "📈 *DAILY TRAFFIC REPORT*\n"
        f"📅 {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
        "📊 Only includes active SNMP devices."
    )
    files = {'document': open(pdf_file, 'rb')}
    data = {'chat_id': CHAT_ID, 'caption': caption_text, 'parse_mode': 'Markdown'}
    try:
        requests.post(url, files=files, data=data, timeout=30)
        print("✅ REPORT SENT!")
    except Exception as e:
        print(f"❌ Telegram Error: {e}")

if __name__ == "__main__":
    try:
        f_name = create_traffic_report()
        if f_name:
            send_telegram(f_name)
            if os.path.exists(f_name):
                os.remove(f_name)
                print("--- Cleanup Complete ---")
    except Exception as e:
        traceback.print_exc()
