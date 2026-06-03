# AutoVSF for Termux

Phiên bản tối ưu hóa cho môi trường **Termux** trên Android.

## 🚀 Hướng dẫn cài đặt

Mở Termux và chạy lệnh sau:

```bash
pkg update && pkg upgrade -y
pkg install git -y
git clone https://github.com/your-repo/autovsf-termux.git
cd autovsf-termux
chmod +x install.sh
./install.sh
```

`install.sh` sẽ tự động thiết lập môi trường Ubuntu (Proot), cài đặt Box64 (giả lập x86_64) và các thư viện cần thiết.

## 🛠 Cách sử dụng

Mọi thao tác hiện tại sẽ chạy bên trong môi trường Ubuntu của Proot để đảm bảo VideoSubFinder hoạt động:

```bash
proot-distro login ubuntu -- bash -c "cd $(pwd) && python3 headless.py <video_path>"
```

## ⚠️ Lưu ý quan trọng
- Lần đầu chạy `./install.sh` có thể mất 5-10 phút để tải và thiết lập môi trường.
- VideoSubFinder chạy qua giả lập **Box64** nên tốc độ có thể chậm hơn trên PC, nhưng đây là cách ổn định nhất để chạy bản Linux chính thức trên Android.
