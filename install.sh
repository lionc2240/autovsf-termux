#!/data/data/com.termux/files/usr/bin/bash
# install_termux.sh - Tối ưu cho Termux trên Android

set -e

echo "🌍 Bắt đầu cài đặt AutoVSF for Termux..."

# 1. Cập nhật và cài đặt các gói cần thiết trong Termux
echo "📦 Đang cài đặt các gói hệ thống..."
pkg update -y
pkg install -y x11-repo
pkg install -y xvfb ffmpeg python opencv-python-static libjpeg-turbo libpng webp-pixbuf-loader wget curl tar

# 2. Cài đặt thư viện Python
echo "🚀 Cài đặt thư viện Python..."
pip install watchdog google-api-python-client google-auth-oauthlib google-auth httplib2 psutil Pillow

# 3. Thông báo về VideoSubFinder (Cần chạy qua Proot-Distro hoặc giả lập)
echo "⚠️ Lưu ý: VideoSubFinder (x86_64) không chạy trực tiếp trên Termux ARM64."
echo "💡 Bạn nên cài đặt 'proot-distro' với Ubuntu để chạy VideoSubFinder."
echo ""
echo "Các bước đề xuất:"
echo "1. pkg install proot-distro"
echo "2. proot-distro install ubuntu"
echo "3. proot-distro login ubuntu"
echo "4. Chạy file install.sh của bản Linux trong môi trường Ubuntu đó."

chmod +x headless.py ocr.py

echo "✅ Cấu hình script hoàn tất!"
