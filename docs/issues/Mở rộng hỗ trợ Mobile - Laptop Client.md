Tôi sẽ nghiên cứu cấu trúc hiện tại để lên kế hoạch mở rộng hỗ trợ người dùng mobile/laptop.

Research client device support

Read [](file:///home/zero-trust-netwoking/control-plane/schemas/node.py#1-1), lines 1 to 100

Read [](file:///home/zero-trust-netwoking/control-plane/database/models.py#1-1), lines 1 to 150

Read [](file:///home/zero-trust-netwoking/control-plane/api/v1/agent.py#1-1), lines 1 to 200

Read [](file:///home/zero-trust-netwoking/control-plane/core/wireguard_service.py)

Read [](file:///home/zero-trust-netwoking/agent/wireguard/config_builder.py#1-1), lines 1 to 200

Read [](file:///home/zero-trust-netwoking/control-plane/schemas/config.py#1-1), lines 1 to 150

Read [](file:///home/zero-trust-netwoking/control-plane/core/policy_engine.py#1-1), lines 1 to 200

Read [](file:///home/zero-trust-netwoking/scripts/hub/install.sh#1-1), lines 1 to 200

Read [](file:///home/zero-trust-netwoking/control-plane/config.py#1-1), lines 1 to 100

Read [](file:///home/zero-trust-netwoking/scripts/hub/install.sh#200-200), lines 200 to 400

Read [](file:///home/zero-trust-netwoking/control-plane/core/policy_engine.py#200-200), lines 200 to 347

Read [](file:///home/zero-trust-netwoking/control-plane/schemas/node.py#100-100), lines 100 to 199

Read [](file:///home/zero-trust-netwoking/scripts/hub/install.sh#400-400), lines 400 to 590

Read [](file:///home/zero-trust-netwoking/policies/global.yaml#1-1), lines 1 to 100

Read [](file:///home/zero-trust-netwoking/agent/wireguard/manager.py#1-1), lines 1 to 50

Read [](file:///home/zero-trust-netwoking/scripts/node/install.sh#1-1), lines 1 to 150

Read [](file:///home/zero-trust-netwoking/control-plane/core/ipam.py#1-1), lines 1 to 100

## Plan: Mở rộng hỗ trợ Mobile/Laptop Client

Mở rộng hệ thống Zero Trust Networking để hỗ trợ người dùng mobile/laptop kết nối qua WireGuard client và truy cập internet an toàn. Hạ tầng NAT/IP forwarding trên Hub đã sẵn sàng, cần bổ sung client role, API đăng ký mới, và config generator cho mobile apps.

### Steps

1. **Thêm `client` role trong schemas**: Mở rộng `NodeRole` enum trong node.py thêm `client` role, và tạo `ClientDeviceCreate` schema với các trường: `user_id`, `device_name`, `device_type` (mobile/laptop), `expires_at`

2. **Tạo `ClientDevice` model trong database**: Bổ sung model mới trong models.py với quan hệ User → nhiều Devices, hỗ trợ device expiration và revocation

3. **Tạo Client Registration API**: Thêm file mới `control-plane/api/v1/client.py` với endpoints:
   - `POST /api/v1/client/register` - Đăng ký device mới (trả về config + QR code)
   - `GET /api/v1/client/config/{device_id}` - Download config file
   - `DELETE /api/v1/client/{device_id}` - Revoke device

4. **Cập nhật Config Builder cho full-tunnel**: Sửa config.py và policy engine để hỗ trợ `AllowedIPs = 0.0.0.0/0, ::/0` cho client role (toàn bộ traffic qua VPN)

5. **Thêm QR Code generator**: Tạo utility function sinh QR code từ WireGuard config để mobile users scan trực tiếp trong app

6. **Cập nhật Hub DNS**: Bổ sung DNS resolver trên Hub (hoặc forward đến `1.1.1.1`, `8.8.8.8`) để client có thể resolve tên miền khi dùng full-tunnel

### Further Considerations

1. **User Authentication**: Có cần tích hợp OAuth/SSO cho user identity không? Hay dùng simple token-based? → Khuyến nghị: Bắt đầu với admin-generated tokens, sau đó mở rộng lên OAuth

2. **Split-tunnel vs Full-tunnel**: Client muốn chỉ route traffic đến overlay (split) hay toàn bộ internet (full)? → Khuyến nghị: Hỗ trợ cả hai qua tham số khi đăng ký

3. **Device limits per user**: Có giới hạn số devices mỗi user không? (VD: max 5 devices) → Khuyến nghị: Có, configurable trong settings