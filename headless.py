import sys, os, time, datetime
from pathlib import Path
import subprocess
import config as C
import ocr

def log(msg):
    print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {msg}")

def run_headless(video_path, top=0.3, bottom=0.0, left=0.0, right=1.0):
    video = os.path.abspath(video_path)
    if not os.path.isfile(video):
        print(f"❌ Không tìm thấy video: {video}")
        return

    # 1. Chạy VideoSubFinder
    cfg = C.load()
    vsf = cfg["vsf_path"]
    out_dir = str(Path(video).parent / (Path(video).stem + "_out"))
    
    log(f"🚀 Bắt đầu quét video: {Path(video).name}")
    log(f"✂️  Vùng quét (Crop): top={top}, bottom={bottom}, left={left}, right={right}")

    cmd = [
        vsf,
        "-c", "-r", 
        "-i", video,
        "-o", out_dir,
        "-te", str(top),
        "-be", str(bottom),
        "-le", str(left),
        "-re", str(right)
    ]

    # VideoSubFinder.run đã tự có xvfb-run bên trong nên gọi trực tiếp
    vsf_dir = os.path.dirname(vsf)
    proc = subprocess.Popen(cmd, cwd=vsf_dir)
    proc.wait()
    log("✅ Quét video xong.")

    # 2. Chạy OCR
    rgb_dir = os.path.join(out_dir, "RGBImages")
    srt_out = os.path.join(out_dir, Path(video).stem + ".srt")
    
    if not os.path.exists(rgb_dir):
        print(f"❌ Không tìm thấy thư mục ảnh: {rgb_dir}")
        return

    log(f"⚡ Bắt đầu OCR ảnh trong: {rgb_dir}")
    
    def on_progress(done, total):
        print(f"\r⏳ Tiến độ OCR: {done}/{total} ảnh", end="")

    def on_finish(path):
        print(f"\n✅ Hoàn thành! File sub: {path}")

    ocr.run(rgb_dir, srt_out, 
            cfg.get("delete_raw_texts", False), 
            cfg.get("delete_texts", False),
            log, on_progress, on_finish)

    # Giữ script chạy cho đến khi OCR xong (vì ocr.run chạy trong thread)
    while True:
        if C.state.done >= C.state.total and C.state.total > 0:
            time.sleep(2) # Chờ ghi file xong
            break
        time.sleep(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Sử dụng: python3 headless.py <đường_dẫn_video>")
    else:
        run_headless(sys.argv[1])
