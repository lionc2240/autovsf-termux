#!/data/data/com.termux/files/usr/bin/bash
# install.sh - Bản vá "Bất tử": Chấp nhận mọi trạng thái của Proot

# KHÔNG dùng set -e ở giai đoạn đầu để tránh chết script khi proot-distro báo 'already exists'
# set -e (Sẽ bật lại sau khi vào Ubuntu)

# ─── 1. KIỂM TRA MÔI TRƯỜNG (HOST vs GUEST) ───────────────────────────────────
# Nếu là user thường (không phải root) và có lệnh pkg -> Đang ở Termux Host
if [ "$(id -u)" != "0" ] && command -v pkg >/dev/null 2>&1; then
    echo "🌍 [Termux Host] Đang khởi động quy trình..."
    
    # Cài proot-distro nếu chưa có
    if ! command -v proot-distro >/dev/null 2>&1; then
        pkg update -y && pkg install proot-distro -y
    fi

    DISTRO="ubuntu"
    
    echo "📥 Đang kiểm tra/cài đặt $DISTRO (nếu đã có sẽ tự bỏ qua)..."
    # Thử cài, nếu lỗi (do đã có) thì cũng không sao, chạy tiếp
    proot-distro install $DISTRO 2>/dev/null || true

    echo "🚀 Chuyển vào môi trường $DISTRO..."
    # Chạy lại chính script này bên trong Ubuntu
    # Dùng $(pwd) để đảm bảo đường dẫn chính xác
    if proot-distro login $DISTRO -- bash -c "cd $(pwd) && bash install.sh"; then
        echo "==========================================================="
        echo "🎉 CÀI ĐẶT HOÀN TẤT!"
        echo "💡 Lệnh chạy AutoVSF:"
        echo "   proot-distro login ubuntu -- bash -c 'cd $(pwd) && python3 headless.py <video>'"
        echo "==========================================================="
        exit 0
    else
        echo "==========================================================="
        echo "❌ CÀI ĐẶT THẤT BẠI! Vui lòng kiểm tra lỗi ở phía trên."
        echo "==========================================================="
        exit 1
    fi
fi

# ─── 2. CHẠY TRÊN UBUNTU (GUEST) ──────────────────────────────────────────────
# Bây giờ mới bật set -e để kiểm soát lỗi trong Ubuntu
set -e

echo "📦 [Ubuntu Guest] Đang thiết lập hệ thống..."

# Tự động sửa lỗi dpkg bị gián đoạn nếu có
echo "🔧 Đang sửa lỗi dpkg (nếu có)..."
dpkg --configure -a

# Dọn dẹp repo cũ (nếu có)
rm -f /etc/apt/sources.list.d/box64.list
rm -f /etc/apt/trusted.gpg.d/box64.gpg

# Thiết lập Multiarch (amd64) để cài các thư viện phụ thuộc cho Box64
echo "🔧 Thiết lập Multiarch (amd64)..."
dpkg --add-architecture amd64

# Giới hạn kho lưu trữ ports.ubuntu.com gốc chỉ phục vụ arm64 để tránh xung đột 404 với amd64
python3 -c '
import os, re

def clean_and_update_line(line):
    # 1. Dọn dẹp và gộp các ngoặc vuông nếu bị trùng lặp/tách rời (do lần chạy lỗi trước đó)
    brackets = re.findall(r"\[([^\]]+)\]", line)
    if len(brackets) > 1:
        merged_opts = []
        for opt in brackets:
            for o in opt.split():
                if o not in merged_opts:
                    merged_opts.append(o)
        line = re.sub(r"\[[^\]]+\]\s*", "", line)
        match = re.match(r"^(\s*deb(?:-src)?\s+)(.*)$", line)
        if match:
            line = f"{match.group(1)}[{chr(32).join(merged_opts)}] {match.group(2)}"

    # 2. Thêm arch=arm64 vào các kho lưu trữ ports.ubuntu.com
    line_stripped = line.strip()
    if not (line_stripped.startswith("deb ") or line_stripped.startswith("deb-src ")):
        return line
    if "ports.ubuntu.com" not in line_stripped:
        return line

    match = re.match(r"^(\s*deb(?:-src)?\s+)\[([^\]]+)\]\s+(.*)$", line)
    if match:
        prefix = match.group(1)
        options_str = match.group(2)
        rest = match.group(3)
        opts = options_str.split()
        has_arch = any(o.startswith("arch=") for o in opts)
        if not has_arch:
            opts.insert(0, "arch=arm64")
        return f"{prefix}[{chr(32).join(opts)}] {rest}"
    else:
        match_no_opt = re.match(r"^(\s*deb(?:-src)?\s+)(.*)$", line)
        if match_no_opt:
            prefix = match_no_opt.group(1)
            rest = match_no_opt.group(2)
            return f"{prefix}[arch=arm64] {rest}"
    return line

def process_list_file(filepath):
    if not os.path.exists(filepath):
        return
    with open(filepath, "r") as f:
        content = f.read()
    new_lines = []
    for line in content.splitlines():
        new_lines.append(clean_and_update_line(line))
    with open(filepath, "w") as f:
        f.write("\n".join(new_lines) + "\n")

# Cập nhật sources.list chính
process_list_file("/etc/apt/sources.list")

# Cập nhật các tệp tin trong sources.list.d
sources_d = "/etc/apt/sources.list.d"
if os.path.exists(sources_d):
    for filename in os.listdir(sources_d):
        filepath = os.path.join(sources_d, filename)
        if filename.endswith(".list"):
            process_list_file(filepath)
        elif filename.endswith(".sources"):
            with open(filepath, "r") as f:
                content = f.read()
            stanzas = content.split("\n\n")
            new_stanzas = []
            for stanza in stanzas:
                if stanza.strip():
                    lines = stanza.splitlines()
                    has_ports = any("ports.ubuntu.com" in l for l in lines)
                    has_arch = any(l.strip().startswith("Architectures:") for l in lines)
                    if has_ports and not has_arch:
                        lines.append("Architectures: arm64")
                    new_stanzas.append("\n".join(lines))
            with open(filepath, "w") as f:
                f.write("\n\n".join(new_stanzas) + "\n\n")
'

# Thêm kho lưu trữ amd64 từ archive.ubuntu.com
CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
if [ -z "$CODENAME" ]; then
    CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
fi
if [ -z "$CODENAME" ]; then
    CODENAME=$(lsb_release -c -s 2>/dev/null || echo "noble")
fi

cat <<EOF > /etc/apt/sources.list.d/amd64.list
deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $CODENAME main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF

# Cập nhật danh sách gói
echo "🔍 Đang cập nhật APT..."
apt-get update -y || echo "⚠️ Một số repository gặp lỗi, vẫn tiếp tục..."

# Cài đặt các công cụ cơ bản
apt-get install -y wget curl xz-utils xvfb ffmpeg python3 python3-pip gnupg2 --ignore-missing

# Cài đặt thư viện đồ họa & âm thanh
echo "🎨 Cài đặt thư viện hệ thống (t64 compatible)..."
DEPS=(
    libxss1 libnss3 libxtst6 libxrender1 libxcomposite1
    libdbus-glib-1-2 libnuma1 libgl1
)
apt-get install -y "${DEPS[@]}" --ignore-missing

# Thử cài bản t64 cho Ubuntu mới, nếu không được thì cài bản thường
apt-get install -y libgtk-3-0t64 || apt-get install -y libgtk-3-0 || true
apt-get install -y libasound2t64 || apt-get install -y libasound2 || true

# Cài đặt các thư viện amd64 cần thiết cho Box64
echo "📦 Cài đặt thư viện amd64 (x86_64 dependencies)..."
apt-get install -y libavcodec-dev:amd64 libavformat-dev:amd64 libswscale-dev:amd64 libavutil-dev:amd64 \
                   libx11-6:amd64 libgl1:amd64 libxml2-dev:amd64 libssl-dev:amd64 --ignore-missing
apt-get install -y libwxgtk3.2-dev:amd64 --ignore-missing || apt-get install -y libwxgtk3.0-gtk3-dev:amd64 --ignore-missing || true

# Cài đặt Box64
if ! command -v box64 &> /dev/null; then
    echo "🚀 Đang cài đặt Box64..."
    curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/box64.gpg
    echo "deb [arch=arm64] https://ryanfortner.github.io/box64-debs/ ./" > /etc/apt/sources.list.d/box64.list
    apt-get update -y || true
    apt-get install box64 -y
else
    echo "✅ Box64 đã sẵn sàng."
fi

# Thiết lập thư mục và Legacy Libs
REPO_DIR=$(pwd)
PARENT_DIR=$(dirname "$REPO_DIR")
VSF_DIR="$PARENT_DIR/VideoSubFinder"
LIBS_DIR="$VSF_DIR/legacy_libs"

echo "🚀 Kiểm tra Legacy Libs (x64)..."
mkdir -p "$LIBS_DIR"
cd "$LIBS_DIR"

declare -A DEBS=(
    ["libaom0"]="https://archive.ubuntu.com/ubuntu/pool/universe/a/aom/libaom0_1.0.0.errata1-3build1_amd64.deb"
    ["libvpx6"]="http://azure.archive.ubuntu.com/ubuntu/pool/main/libv/libvpx/libvpx6_1.8.2-1ubuntu0.4_amd64.deb"
    ["libx264-155"]="https://old-releases.ubuntu.com/ubuntu/pool/universe/x/x264/libx264-155_0.155.2917+git0a84d98-2_amd64.deb"
    ["libx265-179"]="http://ftp.ubuntu.com/ubuntu/ubuntu/pool/universe/x/x265/libx265-179_3.2.1-1build1_amd64.deb"
    ["libflite1"]="https://old-releases.ubuntu.com/ubuntu/pool/universe/f/flite/libflite1_2.1-release-3_amd64.deb"
    ["libwavpack1"]="http://azure.archive.ubuntu.com/ubuntu/pool/main/w/wavpack/libwavpack1_5.2.0-1ubuntu0.1_amd64.deb"
    ["libwebp6"]="http://security.ubuntu.com/ubuntu/pool/main/libw/libwebp/libwebp6_0.6.1-2ubuntu0.20.04.3_amd64.deb"
    ["libcodec2-0.9"]="http://security.ubuntu.com/ubuntu/pool/universe/c/codec2/libcodec2-0.9_0.9.2-2_amd64.deb"
    ["libssh-gcrypt-4"]="https://archive.ubuntu.com/ubuntu/pool/main/libs/libssh/libssh-gcrypt-4_0.9.3-2ubuntu2_amd64.deb"
    ["libbs2b0"]="https://old-releases.ubuntu.com/ubuntu/pool/universe/libb/libbs2b/libbs2b0_3.1.0+dfsg-2.2build1_amd64.deb"
    ["liblilv-0-0"]="http://ftp.ubuntu.com/ubuntu/pool/universe/l/lilv/liblilv-0-0_0.24.6-1_amd64.deb"
    ["librubberband2"]="https://sourceforge.net/projects/makulu/files/repository-14/packages/librubberband2_1.8.1-7ubuntu2_amd64.deb/download"
    ["libmysofa1"]="http://download.nust.na/pub/ubuntu/ubuntu/pool/universe/libm/libmysofa/libmysofa1_1.0~dfsg0-1_amd64.deb"
    ["libass9"]="https://mirror.unej.ac.id/ubuntu/pool/universe/liba/libass/libass9_0.14.0-2_amd64.deb"
    ["libvidstab1.1"]="http://ftp.ubuntu.com/ubuntu/ubuntu/pool/universe/libv/libvidstab/libvidstab1.1_1.1.0-2_amd64.deb"
    ["libxml2"]="https://robohub.eng.uwaterloo.ca/mirror/ubuntu/pool/main/libx/libxml2/libxml2_2.9.10+dfsg-5_amd64.deb"
)

for pkg in "${!DEBS[@]}"; do
    if [ ! -f "${pkg}.so" ] && [ ! -f "${pkg}.so.0" ]; then
        echo "📥 Đang tải $pkg..."
        curl -L -o "$pkg.deb" "${DEBS[$pkg]}"
        dpkg-deb -x "$pkg.deb" .
        find usr/lib/x86_64-linux-gnu/ -name "*.so*" -exec mv {} . \; || true
        rm -rf usr/ "$pkg.deb"
    fi
done

cd "$REPO_DIR"

# Python Libs
echo "🚀 Kiểm tra thư viện Python..."
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow --break-system-packages 2>/dev/null || \
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow

# VideoSubFinder
if [ ! -f "$VSF_DIR/VideoSubFinderWXW" ]; then
    echo "🚀 Tải VideoSubFinder..."
    VSF_LINK="https://github.com/lionc2240/autovsf-codespaces/releases/download/VideoSubFinder_6.10_ubu20.04.tar.xz/VideoSubFinder_6.10_ubu20.04.tar.xz"
    VSF_FILE="VideoSubFinder_6.10_ubu20.04.tar.xz"
    curl -L -o "$PARENT_DIR/$VSF_FILE" "$VSF_LINK"
    tar -xf "$PARENT_DIR/$VSF_FILE" -C "$PARENT_DIR/"
    rm "$PARENT_DIR/$VSF_FILE"
fi

# .run Wrapper
cat <<EOF > "$VSF_DIR/VideoSubFinderWXW.run"
#!/bin/sh
export LD_LIBRARY_PATH="$LIBS_DIR:\$PWD:\$LD_LIBRARY_PATH"
export BOX64_LD_LIBRARY_PATH="$LIBS_DIR:\$PWD:/usr/lib/x86_64-linux-gnu"
export BOX64_EMULATED_LIBS="libOpenCL.so.1:libOpenCL.so"
if [ -z "\$DISPLAY" ]; then
    xvfb-run -a box64 ./VideoSubFinderWXW "\$@"
else
    box64 ./VideoSubFinderWXW "\$@"
fi
EOF

chmod +x "$VSF_DIR/VideoSubFinderWXW" "$VSF_DIR/VideoSubFinderWXW.run"
chmod +x headless.py ocr.py
echo "✅ Cài đặt hoàn tất bên trong Ubuntu."
