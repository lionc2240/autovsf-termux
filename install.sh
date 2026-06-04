#!/data/data/com.termux/files/usr/bin/bash
# install.sh - Tối ưu hóa & Sửa lỗi GPG cho AutoVSF trên Termux
# Hỗ trợ Ubuntu 24.04, 25.10 (Noble, Questing)

set -e

# ─── 1. KIỂM TRA MÔI TRƯỜNG (HOST vs GUEST) ───────────────────────────────────
IS_TERMUX_HOST=false
if [ "$(id -u)" != "0" ] && [ -d "/data/data/com.termux/files/usr" ]; then
    IS_TERMUX_HOST=true
fi

if [ "$IS_TERMUX_HOST" = true ] && [ -z "$PROOT_DISTRO_NAME" ]; then
    echo "🌍 [Termux Host] Đang chuẩn bị môi trường..."
    
    if ! command -v proot-distro >/dev/null 2>&1; then
        pkg update -y && pkg install proot-distro -y
    fi

    DISTRO="ubuntu"
    # Kiểm tra distro đã cài chưa bằng cách kiểm tra thư mục rootfs trực tiếp
    ROOTFS_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/$DISTRO"
    
    if [ -d "$ROOTFS_DIR" ]; then
        echo "✅ $DISTRO đã được cài đặt."
    else
        echo "📥 Đang cài đặt $DISTRO (có thể mất vài phút)..."
        proot-distro install $DISTRO
    fi

    echo "🚀 Chuyển vào môi trường $DISTRO để tiếp tục..."
    proot-distro login $DISTRO -- bash -c "cd $(pwd) && bash install.sh"
    
    echo "==========================================================="
    echo "🎉 CÀI ĐẶT HOÀN TẤT!"
    echo "💡 Lệnh chạy AutoVSF:"
    echo "   proot-distro login ubuntu -- bash -c 'cd $(pwd) && python3 headless.py <video>'"
    echo "==========================================================="
    exit
fi

# ─── 2. CHẠY TRÊN UBUNTU (GUEST) ──────────────────────────────────────────────
echo "📦 [Ubuntu Guest] Đang kiểm tra hệ thống..."

# Làm sạch các repo cũ gây lỗi GPG (đặc biệt là box64 cũ)
rm -f /etc/apt/sources.list.d/box64.list

# Cập nhật repo (không để lỗi GPG làm chết script)
echo "🔍 Đang cập nhật danh sách gói (APT Update)..."
apt-get update -y || echo "⚠️ Cảnh báo: Một số repository không thể cập nhật, tiếp tục..."

# Cài đặt các gói cơ bản (Bao gồm gnupg2 để xử lý key)
apt-get install -y wget curl xz-utils xvfb ffmpeg python3 python3-pip gnupg2 --ignore-missing

# Xử lý các thư viện GUI & Sound
echo "🎨 Đang cài đặt thư viện đồ họa & âm thanh..."
DEPS=(
    libxss1 libnss3 libxtst6 libxrender1 libxcomposite1
    libdbus-glib-1-2 libnuma1 libgl1
)
apt-get install -y "${DEPS[@]}" --ignore-missing

# Xử lý riêng biệt các gói có thể thay đổi tên (t64 cho Noble/Questing)
apt-get install -y libgtk-3-0t64 || apt-get install -y libgtk-3-0 || true
apt-get install -y libasound2t64 || apt-get install -y libasound2 || true

# Cài đặt Box64
if ! command -v box64 &> /dev/null; then
    echo "🚀 Đang cài đặt Box64..."
    # 1. Tải và nạp Key GPG trước
    curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/box64.gpg
    # 2. Thêm Repo chính thức (Dùng định dạng chuẩn cho Box64)
    echo "deb [arch=arm64] https://ryanfortner.github.io/box64-debs/ ./" > /etc/apt/sources.list.d/box64.list
    # 3. Update lại và cài đặt
    apt-get update -y || true
    apt-get install box64 -y
else
    echo "✅ Box64 đã sẵn sàng."
fi

# Thiết lập thư mục làm việc
REPO_DIR=$(pwd)
PARENT_DIR=$(dirname "$REPO_DIR")
VSF_DIR="$PARENT_DIR/VideoSubFinder"
LIBS_DIR="$VSF_DIR/legacy_libs"

# Xử lý thư viện cũ (Legacy Libs - amd64)
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

# Cài đặt Python libs
echo "🚀 Kiểm tra thư viện Python..."
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow --break-system-packages 2>/dev/null || \
pip3 install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 opencv-python psutil Pillow

# Tải VideoSubFinder
if [ ! -f "$VSF_DIR/VideoSubFinderWXW" ]; then
    echo "🚀 Tải VideoSubFinder..."
    VSF_LINK="https://github.com/lionc2240/autovsf-codespaces/releases/download/VideoSubFinder_6.10_ubu20.04.tar.xz/VideoSubFinder_6.10_ubu20.04.tar.xz"
    VSF_FILE="VideoSubFinder_6.10_ubu20.04.tar.xz"
    curl -L -o "$PARENT_DIR/$VSF_FILE" "$VSF_LINK"
    tar -xf "$PARENT_DIR/$VSF_FILE" -C "$PARENT_DIR/"
    rm "$PARENT_DIR/$VSF_FILE"
fi

# Cấu hình file .run
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
echo "✅ Đã hoàn tất cấu hình trong Ubuntu."
