"""ocr.py — OCR engine: upload ảnh lên Drive, lấy text, ghép SRT.
Sử dụng thư viện google-auth-oauthlib hiện đại để tránh lỗi OOB 400.
"""
import io, re, time, shutil, threading, concurrent.futures, os, sys, datetime
from pathlib import Path
from typing import Callable

from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload, MediaIoBaseDownload
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

import config as C

# ── Auth (Modern Version) ───────────────────────────────────────────────────
def get_credentials():
    cred_file = C.credentials_file()
    tok_file  = C.token_file()
    
    if not os.path.exists(cred_file):
        raise FileNotFoundError(f"Không tìm thấy file credentials tại: {cred_file}")

    creds = None
    # Load token đã lưu nếu có
    if os.path.exists(tok_file):
        creds = Credentials.from_authorized_user_file(tok_file, [C.SCOPES])

    # Nếu token không hợp lệ hoặc chưa có, thực hiện đăng nhập mới
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            print("\n" + "="*70)
            print("HƯỚNG DẪN XÁC THỰC CHO CODESPACES (CÁCH CHẮC CHẮN NHẤT):")
            print("1. Nhấn vào đường link 'Auth URL' bên dưới để đăng nhập.")
            print("2. Sau khi nhấn 'Allow', trình duyệt sẽ chuyển đến trang lỗi (localhost).")
            print("3. BẠN HÃY COPY TOÀN BỘ ĐỊA CHỈ (URL) CỦA TRANG LỖI ĐÓ.")
            print("   (Link sẽ có dạng: http://localhost:8080/?state=...&code=...)")
            print("4. Dán cái link bạn vừa copy vào dòng 'Paste URL here' bên dưới.")
            print("="*70 + "\n")

            os.environ['OAUTHLIB_INSECURE_TRANSPORT'] = '1'
            # Sử dụng một port cố định để Google dễ chấp nhận
            redirect_uri = 'http://localhost:8080/'
            flow = InstalledAppFlow.from_client_secrets_file(
                cred_file, 
                scopes=[C.SCOPES],
                redirect_uri=redirect_uri
            )
            
            auth_url, _ = flow.authorization_url(prompt='consent', access_type='offline')
            print(f"Auth URL: {auth_url}")
            
            print("\n")
            response_url = input("Paste URL here: ").strip()
            
            # Khắc phục lỗi nếu người dùng dán link từ Codespaces thay vì localhost
            if "github.dev" in response_url:
                response_url = response_url.replace(response_url.split('/?')[0], "http://localhost:8080")
            
            flow.fetch_token(authorization_response=response_url)
            creds = flow.credentials
            
        # Lưu token cho lần sau
        with open(tok_file, 'w') as token:
            token.write(creds.to_json())
            print(f"\n[OK] Đã lưu token vào {tok_file}")
            
    return creds

# ── Thread-local Drive service ─────────────────────────────────────────────────
_local = threading.local()

def _service(creds):
    if not hasattr(_local, "svc"):
        _local.svc = build("drive", "v3", credentials=creds)
    return _local.svc

# ── Validate folder (1 lần/session) ───────────────────────────────────────────
_folder_validated = False

def _validate_folder(svc, folder_id: str):
    if not folder_id: return
    try:
        svc.files().get(fileId=folder_id, fields="id,name,mimeType").execute()
    except Exception as e:
        raise RuntimeError(f"Lỗi truy cập Drive Folder ID: {e}")

# ── Drive OCR ─────────────────────────────────────────────────────────────────
def _drive_ocr(svc, imgfile: str, imgname: str, folder_id: str) -> str:
    mime = "application/vnd.google-apps.document"
    body = {"name": imgname, "mimeType": mime}
    if folder_id: body["parents"] = [folder_id]

    f = svc.files().create(
        body=body,
        media_body=MediaFileUpload(imgfile, mimetype=mime, resumable=False),
    ).execute()

    file_id = f.get("id")
    try:
        for attempt in range(5):
            try:
                time.sleep(1 + attempt)
                buf = io.BytesIO()
                request = svc.files().export_media(fileId=file_id, mimeType="text/plain")
                downloader = MediaIoBaseDownload(buf, request)
                done = False
                while not done:
                    _, done = downloader.next_chunk()
                break
            except Exception:
                if attempt == 4: raise
        return "".join(buf.getvalue().decode("utf-8").split("\n")[2:])
    finally:
        try: svc.files().delete(fileId=file_id).execute()
        except: pass

def _timestamps(name: str):
    parts = name.split("__")
    if len(parts) < 2: raise ValueError(f"Tên file sai: {name}")
    def fmt(seg):
        t = seg.split("_")
        return f"{t[0][:2]}:{t[1][:2]}:{t[2][:2]},{t[3][:3]}"
    return fmt(parts[0]), fmt(parts[1])

def _ocr_one(image: Path, idx: int, creds, workdir: Path,
             folder_id: str, log: Callable, on_done: Callable):
    global _folder_validated
    st = C.state
    if st.stop_event.is_set(): return
    svc = _service(creds)

    if not _folder_validated:
        try:
            _validate_folder(svc, folder_id)
            _folder_validated = True
        except RuntimeError as e:
            log(f"❌ {e}")
            st.stop_event.set()
            return

    name = image.name
    for attempt in range(1, C.MAX_RETRIES + 1):
        if st.stop_event.is_set(): return
        try:
            text = _drive_ocr(svc, str(image), name, folder_id)
            stem = image.stem
            (workdir / "raw_texts" / f"{stem}.txt").write_text(text, encoding="utf-8")
            (workdir / "texts"     / f"{stem}.txt").write_text(text, encoding="utf-8")
            t0, t1 = _timestamps(name)
            with st.srt_lock:
                st.srt_entries[idx] = [f"{idx}\n", f"{t0} --> {t1}\n", f"{text}\n\n", ""]
            log(f"✅ {text[:60]}...")
            on_done()
            return
        except Exception as e:
            log(f"⚠️ Thử lại {attempt}/{C.MAX_RETRIES}: {e}")
            if attempt == C.MAX_RETRIES: raise
            time.sleep(C.RETRY_DELAY)

def run(images_dir: str, srt_out: str, delete_raw: bool, delete_texts: bool,
        log: Callable, on_progress: Callable, on_finish: Callable):
    cfg = C.load()
    threads = cfg["threads"]
    folder_id = C.state.folder_id or cfg["folder_id"]
    global _folder_validated
    _folder_validated = False
    C.state.reset()
    C.state.t0 = time.time()

    def _run():
        try:
            creds = get_credentials()
            workdir = Path.cwd()
            imgdir = Path(images_dir)
            raw_dir = workdir / "raw_texts"
            txt_dir = workdir / "texts"
            srt_path = Path(srt_out).with_suffix(".srt")

            if not imgdir.exists():
                log(f"❌ Không thấy: {imgdir}"); on_finish(None); return
            raw_dir.mkdir(exist_ok=True); txt_dir.mkdir(exist_ok=True)

            images = [p for ext in C.IMAGE_EXTS for p in imgdir.rglob(ext)]
            C.state.total = len(images)
            log(f"📂 {C.state.total} ảnh | {threads} luồng")
            if not images: log("❌ Không có ảnh."); on_finish(None); return

            def _done():
                C.state.done += 1
                on_progress(C.state.done, C.state.total)

            with concurrent.futures.ThreadPoolExecutor(max_workers=threads) as ex:
                futs = {ex.submit(_ocr_one, img, i+1, creds, workdir, folder_id, log, _done): img 
                        for i, img in enumerate(images)}
                for fut in concurrent.futures.as_completed(futs):
                    if C.state.stop_event.is_set():
                        ex.shutdown(wait=False, cancel_futures=True); break
                    try: fut.result()
                    except Exception as e: log(f"❌ {futs[fut].name}: {e}")

            if C.state.stop_event.is_set(): on_finish(None); return
            srt = "".join("".join(C.state.srt_entries[i]) for i in sorted(C.state.srt_entries))
            srt_path.write_text(srt, encoding="utf-8")
            if cfg.get("nen_raw_texts", False) and raw_dir.exists():
                shutil.make_archive(str(workdir / "raw_texts"), 'zip', root_dir=str(workdir), base_dir="raw_texts")
            for flag, d in ((delete_raw, raw_dir), (delete_texts, txt_dir)):
                if flag and d.exists(): shutil.rmtree(d)
            log(f"✅ Xong → {srt_path}"); on_finish(str(srt_path))
        except Exception as e:
            log(f"❌ Lỗi OCR: {e}"); on_finish(None)

    threading.Thread(target=_run, daemon=True).start()

def _log_cli(msg):
    print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {msg}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Sử dụng: python3 ocr.py <thư_mục_ảnh> [file_srt_đầu_ra]")
        sys.exit(1)
    
    img_dir = sys.argv[1]
    srt_out = sys.argv[2] if len(sys.argv) > 2 else "output.srt"
    
    def _prog(d, t): print(f"\r⏳ OCR: {d}/{t} ảnh", end="")
    def _fin(p): print(f"\n✅ Xong! File: {p}")

    run(img_dir, srt_out, False, False, _log_cli, _prog, _fin)
    
    # Chờ thread hoàn thành
    while True:
        try:
            if C.state.total > 0 and C.state.done >= C.state.total:
                time.sleep(2)
                break
        except KeyboardInterrupt:
            C.state.stop_event.set()
            break
        time.sleep(1)
