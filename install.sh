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
if [ -z "\$DISPLAY" ]; then
    xvfb-run -a box64 ./VideoSubFinderWXW "\$@"
else
    box64 ./VideoSubFinderWXW "\$@"
fi
EOF

chmod +x "$VSF_DIR/VideoSubFinderWXW" "$VSF_DIR/VideoSubFinderWXW.run"
chmod +x headless.py ocr.py
echo "✅ Cài đặt hoàn tất bên trong Ubuntu."
