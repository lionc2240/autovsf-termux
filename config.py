"""config.py — Cấu hình & trạng thái dùng chung. Lưu bằng JSON."""
import json, threading, os
from dataclasses import dataclass, field
from typing import Dict, Optional

# Vị trí thư mục chứa file config.py (thư mục autovsf)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# ── Hằng số ──────────────────────────────────────────────────────────────────
SCOPES             = "https://www.googleapis.com/auth/drive"
APP_NAME           = "VSF OCR Tool"
CONFIG_FILE        = os.path.join(BASE_DIR, "settings.json")
IMAGE_EXTS         = ("*.jpeg", "*.jpg", "*.png", "*.bmp")
MAX_RETRIES        = 5
RETRY_DELAY        = 1

# Tên file mặc định — có thể override trong settings
DEFAULT_CLIENT_SECRET = "credentials.json"
DEFAULT_TOKEN_FILE    = "token.json"

DEFAULT: dict = {
    "folder_id":          "",
    "credentials_file":   DEFAULT_CLIENT_SECRET,
    "token_file":         DEFAULT_TOKEN_FILE,
    "vsf_path":           os.path.abspath(os.path.join(BASE_DIR, "..", "VideoSubFinder", "VideoSubFinderWXW.run")),
    "threads":            20,
    "delete_raw_texts":   False,
    "delete_texts":       False,
    "nen_raw_texts":      False,
    "crop_profiles": {
        "default":    {"top": 0.2102, "bottom": 0.0000, "left": 0.0,    "right": 1.0   },
    },
}

# ── App state ─────────────────────────────────────────────────────────────────
@dataclass
class AppState:
    stop_event:  threading.Event = field(default_factory=threading.Event)
    srt_lock:    threading.Lock  = field(default_factory=threading.Lock)
    srt_entries: Dict[int, list] = field(default_factory=dict)
    folder_id:   str = ""
    total:       int = 0
    done:        int = 0
    t0:          Optional[float] = None
    observer:    object = None

    def reset(self):
        self.stop_event.clear()
        self.srt_entries.clear()
        self.total = self.done = 0
        self.t0 = None

state = AppState()

# ── JSON I/O ──────────────────────────────────────────────────────────────────
def load() -> dict:
    """Đọc settings.json, merge với DEFAULT để đảm bảo không thiếu key."""
    if not os.path.exists(CONFIG_FILE):
        save(DEFAULT.copy())
        return DEFAULT.copy()

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        save(DEFAULT.copy())
        return DEFAULT.copy()

    # Deep merge: DEFAULT là base, data ghi đè
    merged = DEFAULT.copy()
    for k, v in data.items():
        if k == "crop_profiles" and isinstance(v, dict):
            merged["crop_profiles"] = {**DEFAULT["crop_profiles"], **v}
        else:
            merged[k] = v

    return merged


def save(d: dict):
    """Lưu dict ra settings.json với encoding UTF-8."""
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


# Shorthand để lấy token/credentials path từ config hiện tại
def credentials_file() -> str:
    path = load().get("credentials_file", DEFAULT_CLIENT_SECRET)
    if os.path.isabs(path):
        return path
    return os.path.join(BASE_DIR, path)

def token_file() -> str:
    """Token luôn lưu tại thư mục autovsf."""
    path = load().get("token_file", DEFAULT_TOKEN_FILE)
    if os.path.isabs(path):
        return path
    return os.path.join(BASE_DIR, path)

# Backward compat cho ocr.py
CLIENT_SECRET_FILE = property(lambda self: credentials_file())
TOKEN_FILE         = property(lambda self: token_file())
