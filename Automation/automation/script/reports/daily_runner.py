import os
import sys
import requests
import json
from datetime import datetime
import traceback
from backups import generate_report as backup_module
from logs import generate_log_report as log_module
from traffic import generate_traffic_report as traffic_module



TELEGRAM_TOKEN = "8245121645:AAEZjy6vccw3dQOgVud3hWPiF9OqTF9JtfE"
CHAT_ID = "-5105157102"

def send_media_group(files_list):

    if not files_list:
        print("No files to send.")
        return

    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMediaGroup"
    
    media = []
    files_data = {}
    
    caption_text = (
        "DAILY SYSTEM REPORT SUMMARY\n"
        f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
        "Attached: Logs, Traffic, and Backup reports."
    )

    total_files = len(files_list)

    for i, file_path in enumerate(files_list):
        if os.path.exists(file_path):
            file_key = f"file{i}"

            file_caption = caption_text if i == (total_files - 1) else ""
            media.append({
                "type": "document",
                "media": f"attach://{file_key}",
                "caption": file_caption
            })
            
            files_data[file_key] = open(file_path, 'rb')
        else:
            print(f"File not found: {file_path}")

    if not media:
        return

    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "media": json.dumps(media)}, files=files_data, timeout=60)
        
        if r.status_code == 200:
            print("All reports sent in a single message!")
        else:
            print(f"Failed to send group: {r.text}")
    except Exception as e:
        print(f"Telegram Error: {e}")
    finally:
        # Đóng file an toàn
        for f in files_data.values():
            f.close()

def main():
    print("--- STARTING DAILY REPORT ROUTINE ---")
    generated_files = []

    # 1. Log Report
    try:
        print("1. Generating Log Report...") 
        log_pdf = log_module.generate_log_report()
        if log_pdf and os.path.exists(log_pdf): 
            generated_files.append(log_pdf)
        else:
            print("   -> Warning: Log report returned None or file missing.")
    except Exception:
        print("   -> Error generating Log report:")
        traceback.print_exc()

    # 2. Traffic Report
    try:
        print("2. Generating Traffic Report...")
        # Gọi hàm từ module trong thư mục traffic
        traffic_pdf = traffic_module.create_traffic_report()
        if traffic_pdf and os.path.exists(traffic_pdf): 
            generated_files.append(traffic_pdf)
        else:
            print("   -> Warning: Traffic report returned None or file missing.")
    except Exception:
        print("   -> Error generating Traffic report:")
        traceback.print_exc()

    # 3. Backup Report
    try:
        print("3. Generating Backup Report...")
        # Gọi hàm từ module trong thư mục backups
        backup_pdf = backup_module.create_full_report() 
        if backup_pdf and os.path.exists(backup_pdf): 
            generated_files.append(backup_pdf)
        else:
            print("   -> Warning: Backup report returned None or file missing.")
    except Exception:
        print("   -> Error generating Backup report:")
        traceback.print_exc()
    
    if generated_files:
        print(f"Sending {len(generated_files)} files to Telegram...")
        send_media_group(generated_files)
        print("Cleaning up...")
        for f in generated_files:
            if os.path.exists(f):
                os.remove(f)
                print(f"   Deleted: {f}")
        print("--- DONE ---")
    else:
        print("No reports were generated successfully. Nothing to send.")

if __name__ == "__main__":
    main()
