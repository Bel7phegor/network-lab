import requests
from fpdf import FPDF
from datetime import datetime, timedelta
import os
import traceback
import urllib.parse
import re

# ================= CONFIGURATION =================
GRAFANA_URL = "http://192.168.254.254:3000"
LOKI_URL = "http://192.168.254.254:3100"
GRAFANA_TOKEN = "Bearer glsa_fdLTI8mLbIBPHXGhhHiziE5VScbSTvsW_5cc1fbc1" 

# TELEGRAM CREDENTIALS (UPDATED)
TELEGRAM_TOKEN = "8245121645:AAEZjy6vccw3dQOgVud3hWPiF9OqTF9JtfE"            
CHAT_ID = "-5105157102"                                      

DASHBOARD_UID = "loki-final-v4" 

# Panel Settings
PANELS_TO_RENDER = [
    {"id": 2, "name": "Log Volume Trend", "w": 1000, "h": 250, "pdf_w": 170},
    {"id": 4, "name": "Top Sources", "w": 600, "h": 300, "pdf_w": 100}
]

# ================= TEXT HELPER =================
def clean_text(text):
    """
    Sanitize text to be compatible with Latin-1 encoding.
    Removes non-English characters to prevent crashes.
    """
    if not text: return ""
    # Replace newlines and tabs
    text = str(text).replace('\n', ' ').replace('\r', '').replace('\t', ' ')
    # Truncate if too long
    if len(text) > 100:
        text = text[:100] + "..."
    # Encode to Latin-1, replace errors with '?'
    return text.encode('latin-1', 'replace').decode('latin-1')

# ================= 1. LOKI DATA FETCHING =================

def get_active_jobs():
    jobs = []
    try:
        start_time = int((datetime.now() - timedelta(hours=24)).timestamp() * 1e9)
        url = f"{LOKI_URL}/loki/api/v1/label/job/values"
        params = {'start': start_time}
        response = requests.get(url, params=params, timeout=10)
        data = response.json()
        if data.get('status') == 'success':
            jobs = data.get('data', [])
    except:
        print("Error fetching jobs")
    return jobs

def get_job_stats(job_name):
    stats = {"total": 0, "errors": 0, "error_rate": 0.0}
    try:
        # Query 1: Total logs
        q_total = f'sum(count_over_time({{job="{job_name}"}}[24h]))'
        stats["total"] = get_loki_scalar(q_total)

        # Query 2: Error logs
        q_err = f'sum(count_over_time({{job="{job_name}"}} |~ "(?i)error|fail|crit|exception|fatal" [24h]))'
        stats["errors"] = get_loki_scalar(q_err)

        if stats["total"] > 0:
            stats["error_rate"] = (stats["errors"] / stats["total"]) * 100
    except:
        pass
    return stats

def get_recent_errors(job_name, limit=3):
    """
    Fetch raw log content for errors
    """
    errors = []
    try:
        # Simple query for errors
        query = f'{{job="{job_name}"}} |~ "(?i)error|fail|crit|fatal"'
        params = {
            'query': query,
            'limit': limit,
            'start': int((datetime.now() - timedelta(hours=24)).timestamp() * 1e9),
            'end': int(datetime.now().timestamp() * 1e9),
            'direction': 'backward'
        }
        response = requests.get(f"{LOKI_URL}/loki/api/v1/query_range", params=params, timeout=10)
        data = response.json()
        
        if data.get('status') == 'success':
            result = data['data']['result']
            for stream in result:
                for val in stream['values']:
                    # val[1] is the raw log line
                    errors.append(clean_text(val[1]))
    except Exception as e:
        print(f"Error fetching logs for {job_name}: {e}")
    return errors

def get_loki_scalar(query):
    try:
        response = requests.get(f"{LOKI_URL}/loki/api/v1/query", params={'query': query}, timeout=10)
        data = response.json()
        if data.get('status') == 'success' and 'result' in data['data'] and len(data['data']['result']) > 0:
            return int(float(data['data']['result'][0]['value'][1]))
    except:
        pass
    return 0

# ================= 2. GRAFANA RENDERING =================

def get_panel_image(panel_id, w, h, job_name, filename):
    job_safe = urllib.parse.quote(job_name)
    url = (f"{GRAFANA_URL}/render/d-solo/{DASHBOARD_UID}/dashboard"
           f"?orgId=1&panelId={panel_id}&width={w}&height={h}"
           f"&tz=Asia%2FHo_Chi_Minh&from=now-24h&to=now"
           f"&var-job={job_safe}&var-host=All&var-source=All")
    
    headers = {"Authorization": GRAFANA_TOKEN}
    try:
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            with open(filename, 'wb') as f:
                f.write(response.content)
            return True
    except:
        pass
    return False

# ================= 3. PDF GENERATION =================

class PDF(FPDF):
    def header(self):
        self.set_font('Arial', 'B', 10)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, 'Automated Log Audit System', 0, 0, 'R')
        self.ln(10)
    
    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')

# --- ĐÃ SỬA TÊN HÀM Ở ĐÂY TỪ generate_report THÀNH generate_log_report ---
def generate_log_report():
    print("--- STARTING REPORT ---")
    jobs = get_active_jobs()
    if not jobs:
        print("No active jobs found.")
        return None

    pdf = PDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    
    # --- COVER PAGE ---
    pdf.add_page()
    pdf.set_font("Arial", 'B', 24)
    pdf.set_text_color(0, 0, 0)
    pdf.cell(0, 60, "", ln=1)
    pdf.cell(0, 20, "DAILY LOG REPORT", ln=1, align='C')
    pdf.set_font("Arial", '', 12)
    pdf.cell(0, 10, f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", ln=1, align='C')
    pdf.cell(0, 10, f"Services Monitored: {len(jobs)}", ln=1, align='C')
    pdf.ln(20)

    # --- PROCESS JOBS ---
    for job in jobs:
        print(f"Processing: {job}")
        stats = get_job_stats(job)
        
        recent_errors = []
        if stats['errors'] > 0:
            recent_errors = get_recent_errors(job)
        
        pdf.add_page()
        
        # Header
        pdf.set_fill_color(52, 152, 219)
        pdf.set_text_color(255, 255, 255)
        pdf.set_font("Arial", 'B', 14)
        # clean_text ensures no weird chars
        pdf.cell(0, 10, f"  SERVICE: {clean_text(job.upper())}", ln=1, fill=True)
        pdf.set_text_color(0, 0, 0)
        pdf.ln(5)

        # Stats
        pdf.set_font("Arial", '', 10)
        pdf.cell(60, 8, f"Total Logs: {stats['total']:,}")
        
        if stats['error_rate'] > 5:
            pdf.set_text_color(200, 0, 0) # Red
        elif stats['error_rate'] > 0:
            pdf.set_text_color(255, 165, 0) # Orange
            
        pdf.cell(60, 8, f"Errors Found: {stats['errors']:,}")
        pdf.cell(60, 8, f"Rate: {stats['error_rate']:.2f}%")
        pdf.set_text_color(0, 0, 0)
        pdf.ln(10)

        # --- ERROR LOGS ---
        if recent_errors:
            pdf.set_font("Arial", 'B', 10)
            pdf.set_text_color(200, 0, 0)
            # Removed Emoji
            pdf.cell(0, 6, "[!] Latest Critical Error Samples:", ln=1)
            
            pdf.set_font("Courier", '', 8)
            pdf.set_text_color(50, 50, 50)
            
            for line in recent_errors:
                pdf.cell(5, 5, "-", 0, 0) 
                pdf.multi_cell(0, 5, line)
            pdf.ln(5)
        else:
            if stats['errors'] == 0:
                pdf.set_font("Arial", 'I', 9)
                pdf.set_text_color(39, 174, 96) # Green
                # Removed Emoji
                pdf.cell(0, 8, "[OK] System Healthy. No critical errors.", ln=1)
                pdf.ln(5)
        
        pdf.set_text_color(0, 0, 0)

        # --- VISUALIZATIONS ---
        pdf.set_font("Arial", 'B', 11)
        pdf.cell(0, 8, "Visualizations", ln=1)
        
        for panel in PANELS_TO_RENDER:
            img_file = f"temp_{job}_{panel['id']}.png"
            if get_panel_image(panel['id'], panel['w'], panel['h'], job, img_file):
                x_pos = (210 - panel['pdf_w']) / 2
                
                # Page break check
                img_h_mm = (panel['h'] / panel['w']) * panel['pdf_w']
                if pdf.get_y() + img_h_mm > 275:
                    pdf.add_page()

                pdf.image(img_file, x=x_pos, w=panel['pdf_w'])
                os.remove(img_file)
                pdf.ln(2)

    outfile = f"Log_Report_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf"
    pdf.output(outfile)
    return outfile

# ================= 4. TELEGRAM SENDER =================

def send_telegram(pdf_file):
    if not pdf_file: return
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendDocument"
        # Removed Emojis in Caption
        caption = f"LOG REPORT - {datetime.now().strftime('%d/%m/%Y')}"
        files = {'document': open(pdf_file, 'rb')}
        data = {'chat_id': CHAT_ID, 'caption': caption}
        requests.post(url, files=files, data=data, timeout=30)
        print("Report sent to Telegram.")
    except Exception as e:
        print(f"Telegram Error: {e}")

if __name__ == "__main__":
    try:
        # Sửa cả chỗ gọi hàm này nữa cho đồng bộ
        f = generate_log_report()
        if f:
            send_telegram(f)
            if os.path.exists(f): os.remove(f)
            print("--- DONE ---")
    except Exception:
        traceback.print_exc()
