# agent/client.py

def get_base_url():
    # Kiểm tra xem giao diện wg0 có IP chưa
    if has_interface("wg0"):
        return "http://10.0.0.1:8000" # Đi đường hầm (An toàn tuyệt đối)
    else:
        return "https://control-plane.example.com" # Đi đường Internet (Mã hóa SSL)