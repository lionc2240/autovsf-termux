# AutoVSF for Termux

Phiên bản tối ưu hóa cho môi trường **Termux** trên Android.

## 🚀 Hướng dẫn cài đặt

Mở Termux và chạy lệnh sau:

```bash
pkg update && pkg upgrade
pkg install git
git clone https://github.com/lionc2240/autovsf-termux.git
cd autovsf-termux
chmod +x install.sh
./install.sh
```

## ⚠️ Lưu ý quan trọng
VideoSubFinder là một ứng dụng biên dịch cho x86_64 Linux. Để chạy được trên Android (thường là ARM64), bạn cần sử dụng:
1. **Proot-Distro (Ubuntu):** Cách ổn định nhất.
2. **Box64 / FEX-Emu:** Để giả lập kiến trúc x86_64 (Dành cho người dùng nâng cao).

Khuyến khích sử dụng bản `autovsf-linux` bên trong `proot-distro install ubuntu`.

## 🛠 Cách sử dụng
Sau khi cài đặt xong các phụ thuộc Python:
```bash
python headless.py <đường_dẫn_video>
```
