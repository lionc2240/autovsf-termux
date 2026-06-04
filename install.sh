#!/data/data/com.termux/files/usr/bin/bash
# install.sh - Tự động hóa toàn diện cho AutoVSF trên Termux
# Kết hợp Proot-Distro (Ubuntu) và Box64 để chạy VideoSubFinder (x86_64)

set -e

# ─── GIAI ĐOẠN 1: CHẠY TRÊN TERMUX (HOST) ──────────────────────────────────────
if [ -d "/data/data/com.termux/files/usr" ] && [ -z "$PROOT_DISTRO_NAME" ]; then
    echo "🌍 [Termux] Đang chuẩn bị môi trường Proot-Distro..."
    pkg update -y
    pkg install proot-distro -y

    DISTRO="ubuntu"
    # Kiểm tra bằng cả 2 cách: danh sách và thư mục hệ thống
    if proot-distro list | grep -i "$DISTRO" | grep -q "\*" || [ -d "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then
        echo "✅ $DISTRO đã được cài đặt, bỏ qua bước tạo container."
    else
        echo "📥 Đang cài đặt $DISTRO (có thể mất vài phút)..."
        proot-distro install $DISTRO
    fi

    # Gắn kết (bind) thư mục hiện tại vào trong distro và chạy tiếp
    # Lưu ý: proot-distro mặc định chia sẻ /data/data/com.termux/files/home
    echo "🚀 Chuyển vào môi trường $DISTRO để cài đặt VideoSubFinder & Box64..."
    proot-distro login $DISTRO -- bash -c "cd $(pwd) && bash install.sh"
    
    echo "==========================================================="
    echo "🎉 CÀI ĐẶT HOÀN TẤT!"
    echo "💡 Để chạy AutoVSF sau này, hãy dùng lệnh:"
    echo "   proot-distro login ubuntu -- bash -c 'cd $(pwd) && python3 headless.py <video>'"
    echo "==========================================================="
    exit
fi

# ─── GIAI ĐOẠN 2: CHẠY TRÊN UBUNTU (GUEST) ─────────────────────────────────────
echo "📦 [Ubuntu] Đang cập nhật hệ thống và cài đặt công cụ..."
apt-get update -y
apt-get install -y wget curl xz-utils xvfb ffmpeg python3 python3-pip gnupg2 \
                   libxss1 libnss3 libxtst6 libxrender1 libxcomposite1 libasound2 \
                   libdbus-glib-1-2 libnuma1 libgtk-3-0 libgl1

# Cài đặt Box64 (Giả lập x86_64 trên ARM64)
if ! command -v box64 &> /dev/null; then
    echo "🚀 Đang cài đặt Box64..."
    wget https://ryanfortner.github.io/box64-debs/box64.list -O /etc/apt/sources.list.d/box64.list
    wget -qO- https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64.gpg
    apt-get update -y && apt-get install box64 -y
fi

# Thiết lập thư mục
REPO_DIR=$(pwd)
PARENT_DIR=$(dirname "$REPO_DIR")
VSF_DIR="$PARENT_DIR/VideoSubFinder"
LIBS_DIR="$VSF_DIR/legacy_libs"

echo "📂 Thư mục làm việc: $REPO_DIR"

# Xử lý thư viện cũ (Giống bản Colab nhưng dùng cho Box64)
echo "🚀 Kiểm tra và vá lỗi thư viện cũ (Legacy Libs - amd64)..."
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
    if [ ! -f "${pkg}.so" ]; then
        echo "📥 Đang tải $pkg (x64)..."
        curl -L -o "$pkg.deb" "${DEBS[$pkg]}"
        dpkg-deb -x "$pkg.deb" .
        find usr/lib/x86_64-linux-gnu/ -name "*.so*" -exec mv {} . \; || true
        rm -rf usr/ "$pkg.deb"
    fi
done

cd "$REPO_DIR"

echo "🚀 Cài đặt thư viện Python (Ubuntu)..."
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow --break-system-packages || \
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow

echo "🚀 Tải VideoSubFinder..."
VSF_LINK="https://github.com/lionc2240/autovsf-codespaces/releases/download/VideoSubFinder_6.10_ubu20.04.tar.xz/VideoSubFinder_6.10_ubu20.04.tar.xz"
VSF_FILE="VideoSubFinder_6.10_ubu20.04.tar.xz"

if [ ! -f "$VSF_DIR/VideoSubFinderWXW" ]; then
    curl -L -o "$PARENT_DIR/$VSF_FILE" "$VSF_LINK"
    tar -xf "$PARENT_DIR/$VSF_FILE" -C "$PARENT_DIR/"
    rm "$PARENT_DIR/$VSF_FILE"
fi

# Cấu hình file .run (Tối ưu cho Box64 + Termux)
cat <<EOF > "$VSF_DIR/VideoSubFinderWXW.run"
#!/bin/sh
export LD_LIBRARY_PATH="$LIBS_DIR:\$PWD:\$LD_LIBRARY_PATH"
# Box64 cần biết đường dẫn thư viện x64
export BOX64_LD_LIBRARY_PATH="$LIBS_DIR:\$PWD:/usr/lib/x86_64-linux-gnu"

if [ -z "\$DISPLAY" ]; then
    xvfb-run -a box64 ./VideoSubFinderWXW "\$@"
else
    box64 ./VideoSubFinderWXW "\$@"
fi
EOF

chmod +x "$VSF_DIR/VideoSubFinderWXW" "$VSF_DIR/VideoSubFinderWXW.run"
chmod +x headless.py ocr.py
