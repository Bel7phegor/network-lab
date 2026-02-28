import requests

from fpdf import FPDF

from datetime import datetime

import os

import traceback



GRAFANA_URL = "http://192.168.254.254:3000"

PROMETHEUS_URL = "http://192.168.254.254:9090"

GRAFANA_TOKEN = "Bearer glsa_fdLTI8mLbIBPHXGhhHiziE5VScbSTvsW_5cc1fbc1" 

TELEGRAM_TOKEN = "8245121645:AAEZjy6vccw3dQOgVud3hWPiF9OqTF9JtfE"

CHAT_ID = "-5105157102" 

DASHBOARD_UID = "backup-automation-table-view" 

PANELS = [
    {"id": 4, "name": "Overview Statistics", "w": 1000, "h": 200, "pdf_w": 180},        
    {"id": 2, "name": "Backup Timeline", "w": 1000, "h": 300, "pdf_w": 180},    
    {"id": 1, "name": "Device Details", "w": 1000, "h": 600, "pdf_w": 190}        
]


QUERIES = {

    "success_count": 'count(auto_backup_status == 0)',

    "failed_count": 'count(auto_backup_status == 1)',

    "total_count": 'count(auto_backup_status)',

    "failed_hosts": 'auto_backup_status == 1' 

}



def get_metric_value(query):

    try:

        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query}, timeout=10)

        data = response.json()

        if data['status'] == 'success' and len(data['data']['result']) > 0:

            val = float(data['data']['result'][0]['value'][1])

            return int(val)

        return 0

    except Exception:

        return 0



def get_failed_devices_details(query):

    failed_list = []

    try:

        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query}, timeout=10)

        data = response.json()

        

        if data['status'] == 'success':

            for result in data['data']['result']:

                metric_labels = result['metric']

                host = metric_labels.get('host', 'Unknown Device')

                error_msg = metric_labels.get('error', 'No error details provided in labels')

                

                failed_list.append({

                    "host": host,

                    "reason": error_msg

                })

    except Exception:

        traceback.print_exc()

    return failed_list



def get_panel_image(panel_id, width, height, filename):

    url = f"{GRAFANA_URL}/render/d-solo/{DASHBOARD_UID}/dashboard?orgId=1&panelId={panel_id}&width={width}&height={height}&tz=Asia%2FHo_Chi_Minh&from=now-24h&to=now"

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



class PDF(FPDF):

    def header(self):

        self.set_font('Arial', 'B', 10)

        self.cell(0, 10, 'Automated Network Report System', 0, 0, 'R')

        self.ln(10)

    

    def footer(self):

        self.set_y(-15)

        self.set_font('Arial', 'I', 8)

        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')



def create_full_report():

    print("--- 1. Collecting Data ---")

    success_val = get_metric_value(QUERIES["success_count"])

    failed_val = get_metric_value(QUERIES["failed_count"])

    total_val = get_metric_value(QUERIES["total_count"])

    

    failed_devices_details = get_failed_devices_details(QUERIES["failed_hosts"])

    

    success_rate = 0

    if total_val > 0:

        success_rate = (success_val / total_val) * 100



    system_status = "STABLE"

    status_color = (0, 128, 0)

    if failed_val > 0:

        system_status = "WARNING (Check Required)"

        status_color = (200, 0, 0)



    today_str = datetime.now().strftime("%Y-%m-%d %H:%M")



    pdf = PDF()

    pdf.set_auto_page_break(auto=True, margin=20)

    pdf.add_page()

    

    pdf.set_font("Arial", 'B', 20)

    pdf.cell(0, 10, txt="NETWORK BACKUP REPORT", ln=1, align='C')

    pdf.set_font("Arial", 'I', 11)

    pdf.cell(0, 10, txt=f"Date: {today_str} | Period: Last 24 Hours", ln=1, align='C')

    pdf.ln(10)



    pdf.set_fill_color(240, 240, 240)

    pdf.rect(10, pdf.get_y(), 190, 45, 'F')

    

    pdf.set_xy(15, pdf.get_y() + 5)

    pdf.set_font("Arial", 'B', 14)

    pdf.cell(0, 10, txt="1. EXECUTIVE SUMMARY", ln=1)

    

    pdf.set_font("Arial", 'B', 12)

    pdf.set_xy(20, pdf.get_y() + 2)

    pdf.write(5, "Overall Status: ")

    pdf.set_text_color(*status_color)

    pdf.write(5, system_status)

    pdf.set_text_color(0, 0, 0)

    

    pdf.ln(8)

    pdf.set_x(20)

    pdf.set_font("Arial", '', 11)

    pdf.cell(90, 8, txt=f"- Total Devices: {total_val}")

    pdf.cell(90, 8, txt=f"- Success Rate: {success_rate:.1f}%")

    pdf.ln(6)

    pdf.set_x(20)

    pdf.cell(90, 8, txt=f"- Successful: {success_val}")

    pdf.cell(90, 8, txt=f"- Failed: {failed_val}")

    pdf.ln(15)



    pdf.set_font("Arial", 'B', 14)

    pdf.cell(0, 10, txt="2. ISSUE ANALYSIS", ln=1)

    

    if len(failed_devices_details) > 0:

        pdf.set_text_color(200, 0, 0)

        pdf.set_font("Arial", 'B', 11)

        pdf.cell(0, 8, txt="CRITICAL: The following devices failed to backup:", ln=1)

        

        for item in failed_devices_details:

            pdf.set_text_color(0, 0, 0)

            pdf.set_font("Arial", 'B', 11)

            pdf.cell(0, 7, txt=f"   [!] Device: {item['host']}", ln=1)

            

            pdf.set_font("Courier", '', 10)

            pdf.set_text_color(80, 80, 80)

            

            error_text = f"       Error: {item['reason']}"

            pdf.multi_cell(0, 5, txt=error_text)

            pdf.ln(2)



        pdf.ln(5)

        pdf.set_font("Arial", 'I', 10)

        pdf.set_text_color(0, 0, 0)

        pdf.cell(0, 8, txt="Recommendation: Check logs above and verify connectivity.", ln=1)

    else:

        pdf.set_text_color(0, 128, 0)

        pdf.cell(0, 8, txt="All systems normal. No action required.", ln=1)

    

    pdf.set_text_color(0, 0, 0)

    pdf.ln(10)

    

    pdf.set_font("Arial", 'B', 14)

    pdf.cell(0, 10, txt="3. DASHBOARD VISUALIZATION", ln=1, align='L')

    pdf.ln(5)



    print("--- 2. Downloading Images ---")

    

    fig_counter = 1

    for panel in PANELS:

        img_name = f"temp_{panel['id']}.png"

        

        if get_panel_image(panel['id'], panel['w'], panel['h'], img_name):

            img_h_mm = (panel['h'] / panel['w']) * panel['pdf_w']

            

            if pdf.get_y() + img_h_mm + 15 > 270: 

                pdf.add_page()

            

            x_pos = 10

            if panel['pdf_w'] < 190:

                x_pos = (210 - panel['pdf_w']) / 2

                

            pdf.image(img_name, x=x_pos, w=panel['pdf_w'])

            

            pdf.ln(2)

            pdf.set_font("Arial", 'I', 9)

            pdf.cell(0, 5, txt=f"Figure {fig_counter}: {panel['name']}", ln=1, align='C')

            pdf.ln(8)

            

            fig_counter += 1

            os.remove(img_name)

        else:

            pdf.cell(0, 10, txt=f"[Error loading Panel {panel['id']}]", ln=1)



    filename = f"Report_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf"

    pdf.output(filename)

    return filename



def send_telegram(pdf_file):

    if not pdf_file: return

    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendDocument"

    caption_text = (

        "*DAILY NETWORK REPORT*\n"

        f"{datetime.now().strftime('%Y-%m-%d %H:%M')}\n"

        "Report includes detailed error logs."

    )

    files = {'document': open(pdf_file, 'rb')}

    data = {'chat_id': CHAT_ID, 'caption': caption_text, 'parse_mode': 'Markdown'}

    

    try:

        requests.post(url, files=files, data=data, timeout=30)

        print("SENT SUCCESSFULLY!")

    except Exception as e:

        print(f"Telegram Error: {e}")



if __name__ == "__main__":

    try:

        f_name = create_full_report()

        if f_name:

            send_telegram(f_name)

            if os.path.exists(f_name):

                os.remove(f_name)

                print("--- Temporary files cleaned up ---")

    except Exception as e:

        traceback.print_exc() 
