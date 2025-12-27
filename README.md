# Zero Trust Networking Infrastructure

Build a Zero Trust Network using Ansible, WireGuard, and Docker.

Dựa trên tài liệu **NIST Special Publication 800-207: Zero Trust Architecture** mà bạn cung cấp, dưới đây là bản tóm tắt và hướng dẫn thiết kế hệ thống **Zero Trust Networking (ZTA)**. Tài liệu này được cấu trúc để giúp các kiến trúc sư bảo mật và quản trị viên hệ thống hiểu và lên kế hoạch triển khai.

---

# TÀI LIỆU THIẾT KẾ KIẾN TRÚC ZERO TRUST (ZTA)
*(Dựa trên chuẩn NIST SP 800-207)*

## 1. Tổng quan và Định nghĩa
**Zero Trust (ZT)** không phải là một công nghệ đơn lẻ mà là một tập hợp các nguyên tắc an ninh mạng. Tư duy cốt lõi là chuyển dịch từ việc bảo vệ "biên mạng" (network perimeter) tĩnh sang tập trung bảo vệ **người dùng (users), tài sản (assets) và tài nguyên (resources)**.

*   **Nguyên lý căn bản:** "Không bao giờ tin tưởng, luôn luôn xác minh" (Never trust, always verify). Không có sự tin tưởng ngầm định (implicit trust) cho bất kỳ tài sản hay tài khoản người dùng nào chỉ dựa trên vị trí vật lý hoặc vị trí mạng (ví dụ: mạng LAN nội bộ hay Internet).

## 2. Bảy Nguyên tắc Cốt lõi của Zero Trust (The 7 Tenets)
Mọi thiết kế ZTA phải tuân thủ 7 nguyên tắc sau:

1.  **Tất cả dữ liệu và dịch vụ tính toán đều là TÀI NGUYÊN:** Bao gồm cả thiết bị cá nhân (BYOD), thiết bị IoT, và các dịch vụ đám mây (SaaS).
2.  **Bảo mật mọi giao tiếp bất kể vị trí mạng:** Truy cập từ mạng nội bộ cũng phải đáp ứng các tiêu chuẩn bảo mật khắt khe như truy cập từ bên ngoài (mã hóa, xác thực).
3.  **Truy cập tài nguyên được cấp theo từng PHIÊN (Per-session):** Sự tin tưởng được đánh giá lại trước mỗi kết nối. Việc xác thực vào mạng không đồng nghĩa với việc được quyền truy cập vào ứng dụng.
4.  **Truy cập được quyết định bởi CHÍNH SÁCH ĐỘNG (Dynamic Policy):** Quyết định cấp quyền dựa trên:
    *   Danh tính đối tượng (User ID).
    *   Trạng thái thiết bị (Device health/posture).
    *   Hành vi người dùng.
    *   Môi trường (Thời gian, vị trí địa lý).
5.  **Giám sát và đo lường trạng thái an ninh của mọi tài sản:** Không có thiết bị nào là tin cậy tuyệt đối. Hệ thống phải liên tục quét lỗ hổng và trạng thái bản vá (CDM).
6.  **Xác thực và ủy quyền liên tục:** Sử dụng Đa yếu tố xác thực (MFA) và kiểm tra lại liên tục trong suốt quá trình kết nối, không chỉ tại thời điểm đăng nhập.
7.  **Thu thập thông tin để cải thiện bảo mật:** Dùng dữ liệu mạng, log truy cập để phân tích và tối ưu hóa chính sách bảo mật.

## 3. Các Thành phần Logic trong Kiến trúc (Logical Components)

Hệ thống ZTA được chia làm hai phần: **Control Plane** (Mặt phẳng điều khiển) và **Data Plane** (Mặt phẳng dữ liệu).

### A. Core Components (Thành phần cốt lõi)
1.  **Policy Engine (PE - Bộ máy chính sách):** "Bộ não" của hệ thống. Chịu trách nhiệm ra quyết định (Cho phép/Từ chối) dựa trên chính sách và thuật toán tin cậy (Trust Algorithm).
2.  **Policy Administrator (PA - Quản trị chính sách):** Người thực thi quyết định của PE. PA sẽ ra lệnh tạo hoặc ngắt kết nối.
3.  **Policy Enforcement Point (PEP - Điểm thực thi chính sách):** Cổng kết nối (Gateway/Agent). Đây là nơi duy nhất luồng dữ liệu đi qua. PEP chặn mọi truy cập cho đến khi PA cho phép.

### B. Input Data Sources (Nguồn dữ liệu đầu vào cho PE)
Để PE ra quyết định chính xác, cần tích hợp dữ liệu từ:
*   **CDM System:** Trạng thái sức khỏe thiết bị.
*   **Threat Intelligence:** Thông tin về các mối đe dọa mới nhất.
*   **ID Management:** Hệ thống quản lý danh tính (LDAP, AD).
*   **SIEM:** Nhật ký hoạt động và sự kiện bảo mật.

## 4. Các Mô hình Triển khai Phổ biến (Deployment Variations)

Tùy thuộc vào hạ tầng hiện có, bạn có thể chọn một trong các mô hình sau:

1.  **Device Agent/Gateway-Based:**
    *   Cài đặt Agent trên thiết bị người dùng và Gateway trước tài nguyên.
    *   Phù hợp nhất cho doanh nghiệp kiểm soát chặt chẽ thiết bị (Enterprise-owned devices).
2.  **Enclave-Based:**
    *   Gateway đặt trước một nhóm tài nguyên (ví dụ: một trung tâm dữ liệu cũ - Legacy DC).
    *   Phù hợp cho các hệ thống cũ không hỗ trợ cài đặt Agent trực tiếp.
3.  **Resource Portal-Based:**
    *   Gateway đóng vai trò là một cổng web (Portal). Người dùng truy cập qua trình duyệt.
    *   Phù hợp cho BYOD hoặc đối tác bên ngoài (Contractors) mà không cần cài Agent.
4.  **Application Sandboxing:**
    *   Chạy ứng dụng trong các container/máy ảo cô lập trên thiết bị.

## 5. Thuật toán Tin cậy (Trust Algorithm)
Quyết định truy cập dựa trên công thức:
`Truy cập = f(Người dùng, Thiết bị, Ngữ cảnh, Mức độ nhạy cảm của dữ liệu)`

*   **Criteria-based:** Dựa trên tiêu chí cứng (Ví dụ: Phải thuộc nhóm Admin VÀ thiết bị đã update Windows mới nhất).
*   **Score-based:** Tính điểm tin cậy (Confidence Score). Nếu điểm > ngưỡng quy định -> Cho phép.

## 6. Lộ trình Chuyển đổi sang ZTA (Migration Roadmap)

Việc chuyển đổi không thể diễn ra trong một sớm một chiều. NIST đề xuất quy trình sau:

1.  **Xác định Đối tượng (Actors):** Ai là nhân viên, ai là đối tác, các tài khoản dịch vụ (non-person entities).
2.  **Xác định Tài sản (Assets):** Kiểm kê toàn bộ thiết bị và dữ liệu (Data classification).
3.  **Xác định Quy trình nghiệp vụ (Business Processes):** Chọn một quy trình ít rủi ro để thử nghiệm trước.
4.  **Xây dựng Chính sách (Formulating Policies):** Ai được truy cập cái gì, trong điều kiện nào? (Whitelist approach).
5.  **Lựa chọn Giải pháp (Identifying Solutions):** Chọn công nghệ phù hợp (SDP, Micro-segmentation, Identity-aware proxy...).
6.  **Triển khai ban đầu & Giám sát (Initial Deployment):** Chạy ở chế độ "Chỉ theo dõi" (Audit/Log only) để tinh chỉnh chính sách, tránh làm gián đoạn công việc.
7.  **Mở rộng (Expanding):** Áp dụng chế độ thực thi (Enforcement) và mở rộng sang các quy trình nghiệp vụ khác.

## 7. Các Mối đe dọa & Rủi ro
Khi triển khai ZTA, cần lưu ý:
*   **Tấn công vào Control Plane (PE/PA):** Nếu PE/PA bị chiếm quyền hoặc bị DDoS, toàn bộ hoạt động truy cập sẽ bị tê liệt. Cần bảo vệ kỹ lưỡng các thành phần này.
*   **Đánh cắp tài khoản (Stolen Credentials):** ZTA giảm thiểu rủi ro này bằng MFA và Trust Algorithm ngữ cảnh (ví dụ: phát hiện hành vi bất thường dù đúng mật khẩu), nhưng không loại bỏ hoàn toàn.
*   **Phụ thuộc vào nhà cung cấp (Vendor Lock-in):** Do thiếu các tiêu chuẩn giao tiếp chung giữa các thành phần ZT.

---
*Tài liệu này tóm tắt các điểm chính yếu từ NIST SP 800-207 để hỗ trợ việc thiết kế hệ thống bảo mật hiện đại.*
Dựa trên nguyên lý **NIST SP 800-207** và yêu cầu tự chủ (Self-hosted Custom WireGuard) mà bạn đã chọn, đây là cấu trúc thư mục chuẩn cho dự án `zero-trust-networking`.

Cấu trúc này được thiết kế theo mô hình **Monorepo** để dễ quản lý phiên bản đồng nhất giữa Control Plane (Server) và Agent (Client).

### Cấu trúc thư mục tổng quát

```text
zero-trust-networking/
├── control-plane/           # (NÃO BỘ) Server quản lý trung tâm - FastAPI
│   ├── api/                 # REST API endpoints (Agent & Admin)
│   ├── core/                # Logic nghiệp vụ: Trust Engine, IPAM, Policy
│   ├── database/            # SQLAlchemy models + Alembic migrations
│   ├── schemas/             # Pydantic schemas cho validation
│   └── policy-engine/       # (PDP) Compiler chuyển Policy → Config
│
├── agent/                   # (TAY CHÂN) Daemon chạy trên từng VPS
│   ├── wireguard/           # Quản lý WireGuard interface & peers
│   ├── firewall/            # (PEP) Thực thi ACL qua iptables/nftables
│   └── collectors/          # Thu thập dữ liệu cho Trust Algorithm
│
├── policies/                # (LUẬT) Policy-as-Code định nghĩa bằng YAML
│   ├── roles/               # Role-based policies (app, database, ops)
│   └── users/               # User-to-role mappings
│
├── infrastructure/          # (CƠ BẮP) Automation & Deployment
│   ├── ansible/             # Playbooks, roles, inventory
│   └── docker/              # Dockerfile & Caddy config
│
├── scripts/                 # CLI tools & Installation scripts
│   ├── hub/                 # Scripts cài đặt Hub (Control Plane)
│   ├── node/                # Scripts cài đặt Node (Agent)
│   ├── policy/              # Scripts apply policies
│   └── lib/                 # Shared shell functions
│
├── docs/                    # Tài liệu kiến trúc, workflow, issues
├── tests/                   # Integration & E2E testing
├── web-ui/                  # (Optional) Dashboard quản trị
│
├── docker-compose.yml       # Dev environment (Control Plane + Traefik)
├── pyproject.toml           # UV workspace configuration
└── README.md
```

---

### Chi tiết từng thành phần (Deep Dive)

#### 1. `control-plane/` — Policy Decision Point (PDP) & Policy Administrator (PA)

Đây là **"Bộ não"** của hệ thống Zero Trust. FastAPI server xử lý đăng ký node, tính toán Trust Score, và phân phối cấu hình WireGuard + Firewall rules.

```text
control-plane/
├── main.py                  # FastAPI entrypoint với lifespan management
├── config.py                # Pydantic Settings (env vars, WG network, timeouts)
├── schemas.py               # Root-level schemas
│
├── api/
│   └── v1/
│       ├── agent.py         # Agent API: /register, /sync, /heartbeat
│       ├── admin.py         # Admin API: /nodes, /policies (X-Admin-Token auth)
│       └── endpoints.py     # Legacy endpoints (backward compatible)
│
├── core/                    # ⭐ LOGIC NGHIỆP VỤ CỐT LÕI
│   ├── trust_engine.py      # Dynamic Trust Scoring theo NIST SP 800-207
│   ├── policy_engine.py     # Compile policies → firewall rules, allowed peers
│   ├── node_manager.py      # Node lifecycle: register, approve, suspend, revoke
│   ├── ipam.py              # IP Address Management (cấp phát overlay IPs)
│   ├── wireguard_service.py # Quản lý WireGuard peers trên Hub server
│   └── key_manager.py       # Quản lý Public/Private keys
│
├── database/
│   ├── models.py            # SQLAlchemy: Node, Policy, TrustHistory, AuditLog
│   ├── session.py           # Database session management (SQLite/PostgreSQL)
│   └── migrations/          # Alembic migration scripts
│
├── schemas/                 # Pydantic schemas tách biệt
│   ├── node.py              # NodeCreate, NodeResponse, NodeRole, NodeStatus
│   ├── policy.py            # PolicyCreate, Protocol, Action enums
│   ├── config.py            # PeerConfig, InterfaceConfig, AgentConfig
│   └── base.py              # BaseResponse schemas
│
└── policy-engine/
    ├── compiler.py          # Chuyển Policy YAML → WireGuard + iptables config
    └── evaluator.py         # (Reserved) Advanced trust evaluation
```

**Điểm nhấn kiến trúc:**

| Module | Vai trò theo NIST 800-207 |
|--------|---------------------------|
| `trust_engine.py` | Tính **Trust Score** dựa trên: role weight, device health, behavior analysis, security events |
| `policy_engine.py` | **Policy Decision Point** - quyết định node nào được giao tiếp với node nào |
| `node_manager.py` | Quản lý lifecycle: `pending` → `active` → `suspended` → `revoked` |
| `wireguard_service.py` | Cập nhật WireGuard peers trên Hub khi có node mới/bị revoke |

#### 2. `agent/` — Policy Enforcement Point (PEP)

Daemon Python chạy trên mỗi VPS. Thu thập thông tin, đồng bộ cấu hình từ Control Plane, và **thực thi Zero Trust** tại điểm cuối.

```text
agent/
├── agent.py                 # Main daemon: registration, periodic sync, apply config
├── client.py                # HTTP client với auto-failover (overlay ↔ public URL)
├── pyproject.toml           # Agent dependencies
│
├── wireguard/
│   ├── manager.py           # WireGuard interface lifecycle: up/down, add/remove peers
│   └── config_builder.py    # Sinh file wg0.conf từ API response
│
├── firewall/
│   ├── iptables.py          # IPTables manager với dedicated ZT_ACL chain
│   └── nftables.py          # (Future) nftables support
│
└── collectors/              # ⭐ THU THẬP DỮ LIỆU CHO TRUST ALGORITHM
    ├── host_info.py         # OS, platform, distro, kernel version
    ├── network_stats.py     # Connection patterns, traffic metrics, WG stats
    └── security_events.py   # SSH failures, firewall violations, suspicious processes
```

**Workflow của Agent:**

```
┌─────────────────────────────────────────────────────────────────┐
│  Agent Startup                                                   │
├─────────────────────────────────────────────────────────────────┤
│  1. Generate WireGuard keypair (if not exists)                  │
│  2. Collect host_info, security_events, network_stats           │
│  3. POST /api/v1/agent/register với public_key + device_info    │
│  4. Wait for approval (status: pending → active)                │
├─────────────────────────────────────────────────────────────────┤
│  Periodic Sync Loop (every 60s)                                  │
├─────────────────────────────────────────────────────────────────┤
│  1. POST /api/v1/agent/sync với current device_info             │
│  2. Receive: interface config, peers list, firewall rules       │
│  3. Apply WireGuard config (wg syncconf / wg-quick)             │
│  4. Apply iptables rules (ZT_ACL chain)                         │
│  5. POST /api/v1/agent/heartbeat                                │
└─────────────────────────────────────────────────────────────────┘
```

**Điểm nhấn:** Module `firewall/iptables.py` tạo chain `ZT_ACL` riêng biệt để quản lý rules mà không ảnh hưởng đến các rules hệ thống khác.

#### 3. `policies/` — Policy as Code

Định nghĩa chính sách bằng YAML để version control và code review. Control Plane đọc và compile thành firewall rules.

```text
policies/
├── global.yaml              # Default policies: deny-all, zones, base rules
│
├── roles/
│   ├── database.yaml        # DB policies: allow replication, app access
│   ├── app.yaml             # App policies: access to DB, inter-app comm
│   └── ops.yaml             # Ops policies: SSH everywhere, metrics collection
│
└── users/
    └── admin-team.yaml      # User → Role mappings
```

**Ví dụ `global.yaml`:**

```yaml
metadata:
  name: global-policy
  version: "1.0"
  description: "Global Zero Trust policies"

default_action: deny          # DENY ALL by default (Zero Trust)

zones:
  hub:
    description: "Control Plane zone"
    trust_level: 100
  internal:
    description: "Internal services"
    trust_level: 80

base_rules:
  - name: allow-wireguard
    protocol: udp
    port: 51820
    action: allow

  - name: allow-icmp
    protocol: icmp
    action: allow
    rate_limit: "10/second"
```

**Ví dụ `roles/database.yaml`:**

```yaml
metadata:
  name: database-role

inbound:
  - name: app-to-postgres
    from_role: app
    protocol: tcp
    port: 5432
    action: allow

  - name: ops-admin-access
    from_role: ops
    protocol: tcp
    ports: [5432, 6379, 22]
    action: allow

outbound:
  - name: db-replication
    to_role: database
    protocol: tcp
    port: 5432
    action: allow
```

#### 4. `infrastructure/` — Ansible & Docker Deployment

Automation để triển khai hệ thống lên production.

```text
infrastructure/
├── ansible/
│   ├── ansible.cfg              # Ansible configuration
│   ├── site.yml                 # Master playbook (full deployment)
│   ├── deploy-site.yml          # Phased deployment orchestrator
│   │
│   ├── inventory/
│   │   ├── hosts.ini.example    # Production inventory template
│   │   ├── local.ini            # Local testing inventory
│   │   └── group_vars/
│   │       ├── all.yml          # Global variables
│   │       ├── hub.yml          # Hub-specific vars
│   │       ├── app.yml          # App nodes vars
│   │       ├── db.yml           # Database nodes vars
│   │       └── ops.yml          # Ops nodes vars
│   │
│   ├── playbook/
│   │   ├── deploy-hub.yml       # Deploy Hub (Control Plane + WireGuard)
│   │   ├── deploy-agents.yml    # Deploy Agents to nodes
│   │   ├── setup-wireguard.yml  # WireGuard setup only
│   │   ├── sync-policies.yml    # Sync YAML policies to database
│   │   └── templates/           # Jinja2 templates
│   │
│   └── roles/
│       ├── common/              # Base system setup (Python, dependencies)
│       ├── wireguard/           # WireGuard installation
│       ├── control-plane/       # Control Plane deployment
│       └── agent/               # Agent deployment as systemd service
│
└── docker/
    ├── Dockerfile.control       # Multi-stage build với UV package manager
    └── Caddyfile                # Caddy reverse proxy configuration
```

**Deployment Phases (trong `deploy-site.yml`):**

| Phase | Playbook | Mô tả |
|-------|----------|-------|
| 0 | Preflight | Kiểm tra connectivity, dependencies |
| 1 | `deploy-hub.yml` | Cài Control Plane + WireGuard Hub |
| 2 | `deploy-agents.yml` | Cài Agent trên tất cả nodes |
| 3 | Verify | Health check, test connectivity |

#### 5. `scripts/` — CLI Tools & Installation Scripts

Scripts để cài đặt nhanh và quản trị hệ thống.

```text
scripts/
├── ztctl                    # ⭐ CLI Admin Tool
├── install.sh               # Quick install (hub hoặc node)
├── install-agent.sh         # Agent-only installation
│
├── hub/
│   ├── install.sh           # Full Hub installation (590+ lines)
│   ├── uninstall.sh         # Clean uninstall
│   └── add-secondary.sh     # Add secondary Hub (HA)
│
├── node/
│   ├── install.sh           # Node/Agent installation (517+ lines)
│   └── uninstall.sh         # Clean uninstall
│
├── policy/
│   └── apply.sh             # Apply policies from YAML files
│
└── lib/
    └── common.sh            # Shared shell functions
```

**`ztctl` — Zero Trust Control CLI:**

```bash
# Node management
ztctl node list              # Liệt kê tất cả nodes
ztctl node show <hostname>   # Chi tiết node
ztctl node approve <hostname> # Approve pending node
ztctl node remove <hostname>  # Remove node

# Policy management
ztctl policy list            # Liệt kê policies
ztctl policy allow <src> <dst> <port>  # Tạo allow rule
ztctl policy deny <src> <dst> <port>   # Tạo deny rule
ztctl policy remove <id>     # Xóa policy
```

#### 6. `docs/` — Documentation

```text
docs/
├── NIST.SP.800-207.md       # NIST Zero Trust Architecture reference
├── README.MD                # Documentation index
├── WORKFLOW.md              # ⭐ Workflow design với architecture diagrams
│
├── chat/                    # Development session logs
│   └── YYYY-MM-DD_HHhMM.md
│
├── issues/                  # Issue tracking documents
│   └── *.md
│
└── references/
    └── zero-trust-security-model.md
```

#### 7. `tests/` — Testing

```text
tests/
├── uninstall.sh             # Test cleanup script
│
├── agent/
│   ├── agent_test.sh        # Agent functionality tests
│   ├── install_agent_test.sh
│   └── test_case.md         # Test cases documentation
│
├── control-plane/
│   ├── connection_test.sh   # API connectivity tests
│   ├── peer_test.sh         # WireGuard peer tests
│   ├── endpoint/            # API endpoint tests
│   └── caddy/               # Reverse proxy tests
│
├── ansible/
│   └── playbook/            # Ansible playbook tests
│
└── install/
    └── new_install_test.sh  # Fresh installation tests
```

#### 8. Root Files

| File | Mô tả |
|------|-------|
| `docker-compose.yml` | Dev environment: control-plane, traefik, caddy |
| `pyproject.toml` | UV workspace config (members: control-plane, agent) |
| `README.md` | Tài liệu này |

---

### Workflow hoạt động (End-to-End Example)

#### Phase 1: Khởi tạo hệ thống

```bash
# 1. Deploy Hub (VPS-1)
cd infrastructure/ansible
ansible-playbook -i inventory/hosts.ini playbook/deploy-hub.yml

# 2. Deploy Agents (VPS-2: App, VPS-3: DB)
ansible-playbook -i inventory/hosts.ini playbook/deploy-agents.yml
```

#### Phase 2: Node Registration & Approval

```
┌─────────────┐         ┌─────────────────┐         ┌─────────────┐
│   VPS-3     │         │  Control Plane  │         │   Admin     │
│  (DB Agent) │         │     (Hub)       │         │  (ztctl)    │
└──────┬──────┘         └────────┬────────┘         └──────┬──────┘
       │                         │                         │
       │ POST /register          │                         │
       │ {role: database,        │                         │
       │  public_key: xxx,       │                         │
       │  device_info: {...}}    │                         │
       │────────────────────────>│                         │
       │                         │                         │
       │     {status: pending}   │                         │
       │<────────────────────────│                         │
       │                         │                         │
       │                         │   ztctl node list       │
       │                         │<────────────────────────│
       │                         │                         │
       │                         │   ztctl node approve    │
       │                         │        vps-3            │
       │                         │<────────────────────────│
       │                         │                         │
       │                         │ Trust Engine calculates │
       │                         │ trust_score = 85        │
       │                         │ risk_level = low        │
       │                         │                         │
```

#### Phase 3: Configuration Sync

```
┌─────────────┐         ┌─────────────────┐
│   VPS-3     │         │  Control Plane  │
│  (DB Agent) │         │                 │
└──────┬──────┘         └────────┬────────┘
       │                         │
       │ POST /sync              │
       │ {device_info: {...}}    │
       │────────────────────────>│
       │                         │
       │                         │ Policy Engine:
       │                         │ - DB role needs peers: Hub, App
       │                         │ - Firewall: ALLOW 5432 from App
       │                         │
       │ {                       │
       │   interface: {          │
       │     address: 10.10.0.3, │
       │     private_key: xxx    │
       │   },                    │
       │   peers: [hub, app],    │
       │   firewall_rules: [     │
       │     {src: 10.10.0.2,    │
       │      port: 5432,        │
       │      action: ACCEPT}    │
       │   ]                     │
       │ }                       │
       │<────────────────────────│
       │                         │
       │ Agent applies:          │
       │ - wg syncconf wg0       │
       │ - iptables -A ZT_ACL... │
       │                         │
```

#### Kết quả: Zero Trust Achieved

```
┌─────────────────────────────────────────────────────────────────┐
│                     WireGuard Overlay Network                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  VPS-1 Hub  │    │  VPS-2 App  │    │  VPS-3 DB   │         │
│  │  10.10.0.1  │────│  10.10.0.2  │────│  10.10.0.3  │         │
│  │             │    │             │    │             │         │
│  │ Control     │    │ Odoo        │    │ PostgreSQL  │         │
│  │ Plane       │    │             │    │             │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                            │                  │                 │
│                            │   TCP 5432 ✅    │                 │
│                            │─────────────────>│                 │
│                            │                  │                 │
│                            │   SSH 22 ❌      │                 │
│                            │────────X────────>│                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

✅ VPS-2 (App) có thể kết nối PostgreSQL port 5432 trên VPS-3
❌ VPS-2 (App) KHÔNG thể SSH vào VPS-3 (bị chặn bởi iptables)
✅ Chỉ role:ops mới được SSH vào tất cả nodes
```

---

### Trust Algorithm Implementation

Hệ thống implement **Dynamic Trust Scoring** theo NIST SP 800-207:

```python
# Trong trust_engine.py
trust_score = calculate_trust_score(
    role_weight=30,           # Weight theo role (ops > app > db)
    device_health=25,         # OS updated, no vulnerabilities
    behavior_score=25,        # Connection patterns, traffic analysis
    security_events=20        # SSH failures, firewall violations
)

# Risk levels
if trust_score >= 80: risk_level = "low"
elif trust_score >= 60: risk_level = "medium"
elif trust_score >= 40: risk_level = "high"
else: risk_level = "critical"

# Actions based on risk
if risk_level == "critical":
    action = "isolate"        # Revoke all peers, block traffic
elif risk_level == "high":
    action = "restrict"       # Limit peers, enhanced monitoring
else:
    action = "allow"          # Normal operation
```

**Trust History Tracking:**

```sql
-- Mỗi lần sync, trust score được lưu lại
SELECT hostname, trust_score, previous_score, risk_level, action_taken
FROM trust_history
WHERE hostname='vps-3'
ORDER BY calculated_at DESC;

┌───────────┬─────────────┬────────────────┬────────────┬──────────────┐
│ hostname  │ trust_score │ previous_score │ risk_level │ action_taken │
├───────────┼─────────────┼────────────────┼────────────┼──────────────┤
│ vps-3     │ 85          │ 82             │ low        │ allow        │
│ vps-3     │ 82          │ 80             │ low        │ allow        │
│ vps-3     │ 80          │ NULL           │ low        │ allow        │
└───────────┴─────────────┴────────────────┴────────────┴──────────────┘
```

---

### Quick Start

```bash
# Clone repository
git clone https://github.com/your-org/zero-trust-networking.git
cd zero-trust-networking

# Option 1: Script installation
# Trên Hub server:
sudo ./scripts/hub/install.sh

# Trên Node servers:
sudo ./scripts/node/install.sh --hub-url https://hub.example.com

# Option 2: Ansible deployment
cd infrastructure/ansible
cp inventory/hosts.ini.example inventory/hosts.ini
# Edit inventory với IP các servers
ansible-playbook -i inventory/hosts.ini site.yml

# Option 3: Docker (development)
docker-compose up -d
```

---

### Công nghệ sử dụng

| Component | Technology | Lý do chọn |
|-----------|------------|------------|
| Control Plane | FastAPI + SQLAlchemy | Async, type-safe, ORM mạnh |
| Agent | Python + systemd | Nhẹ, ổn định, dễ debug |
| VPN | WireGuard | Hiệu năng cao, modern crypto |
| Firewall | iptables | Universal, stable, well-documented |
| Deployment | Ansible | Agentless, declarative, idempotent |
| Reverse Proxy | Caddy/Traefik | Auto HTTPS, config đơn giản |
| Database | SQLite/PostgreSQL | SQLite cho dev, Postgres cho production |

---

## Client VPN Access (Mobile/Laptop)

Hệ thống hỗ trợ người dùng kết nối từ **mobile (iOS/Android)** và **laptop (Windows/macOS/Linux)** để truy cập internet an toàn qua VPN.

### Tính năng

| Tính năng | Mô tả |
|-----------|-------|
| **Server-side key generation** | Keys được sinh trên server, user không cần tạo |
| **QR Code** | Scan trực tiếp vào WireGuard app trên mobile |
| **Full-tunnel VPN** | Toàn bộ traffic đi qua VPN (`0.0.0.0/0`) |
| **Split-tunnel** | Chỉ traffic đến overlay network đi qua VPN |
| **Config expiration** | Tự động hết hạn sau N ngày (configurable) |
| **Multi-device per user** | Mỗi user có thể có nhiều devices (giới hạn 5) |

### Kiến trúc Client Access

```
┌─────────────────────────────────────────────────────────────────────┐
│                        INTERNET                                      │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │      Hub Server           │
              │   (WireGuard Gateway)     │
              │                           │
              │  ┌─────────────────────┐  │
              │  │ Control Plane API   │  │
              │  │ - /api/v1/client/*  │  │
              │  └─────────────────────┘  │
              │                           │
              │  ┌─────────────────────┐  │
              │  │ WireGuard Interface │  │
              │  │ wg0: 10.10.0.1/24   │  │
              │  │ + NAT Masquerade    │  │
              │  └─────────────────────┘  │
              └─────────────┬─────────────┘
                            │ WireGuard Tunnel
           ┌────────────────┼────────────────┐
           │                │                │
    ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐
    │   iPhone    │  │   MacBook   │  │  Android    │
    │ 10.10.0.100 │  │ 10.10.0.101 │  │ 10.10.0.102 │
    │             │  │             │  │             │
    │ WireGuard   │  │ WireGuard   │  │ WireGuard   │
    │    App      │  │   Client    │  │    App      │
    └─────────────┘  └─────────────┘  └─────────────┘
```

### API Endpoints cho Client Devices

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| `POST` | `/api/v1/client/devices` | Tạo device mới (Admin) |
| `GET` | `/api/v1/client/devices` | Liệt kê devices (Admin) |
| `GET` | `/api/v1/client/devices/{id}` | Chi tiết device (Admin) |
| `DELETE` | `/api/v1/client/devices/{id}` | Revoke device (Admin) |
| `GET` | `/api/v1/client/config/{token}` | Lấy config + QR code |
| `GET` | `/api/v1/client/config/{token}/raw` | Download file .conf |
| `GET` | `/api/v1/client/config/{token}/qr` | Lấy QR code image |

### Hướng dẫn sử dụng

#### 1. Admin tạo device cho user

```bash
# Sử dụng curl
curl -X POST "https://hub.example.com/api/v1/client/devices" \
  -H "X-Admin-Token: your-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "device_name": "iPhone-John",
    "device_type": "mobile",
    "user_id": "john.doe@company.com",
    "tunnel_mode": "full",
    "expires_days": 30
  }'

# Response:
{
  "id": 1,
  "device_name": "iPhone-John",
  "device_type": "mobile",
  "tunnel_mode": "full",
  "status": "active",
  "overlay_ip": "10.10.0.100/24",
  "config_token": "abc123xyz...",
  "expires_at": "2026-01-26T00:00:00Z"
}
```

#### 2. User scan QR code hoặc download config

**Mobile (iOS/Android):**
1. Mở link: `https://hub.example.com/api/v1/client/config/{token}/qr`
2. Mở WireGuard app → Add Tunnel → Create from QR code
3. Scan QR code → Kết nối

**Laptop (Windows/macOS/Linux):**
1. Download: `https://hub.example.com/api/v1/client/config/{token}/raw`
2. Lưu file `iPhone-John.conf`
3. Import vào WireGuard client
4. Activate tunnel

#### 3. Tunnel Modes

**Full-tunnel (mặc định):**
```ini
[Peer]
AllowedIPs = 0.0.0.0/0, ::/0
```
- Toàn bộ internet traffic đi qua VPN
- Bảo vệ khỏi public WiFi không an toàn
- Ẩn IP thật của user

**Split-tunnel:**
```ini
[Peer]
AllowedIPs = 10.10.0.0/24
```
- Chỉ traffic đến overlay network đi qua VPN
- Internet traffic vẫn đi trực tiếp
- Tiết kiệm bandwidth trên Hub

### Config mẫu cho Mobile

```ini
[Interface]
PrivateKey = <auto-generated>
Address = 10.10.0.100/24
DNS = 10.10.0.1, 1.1.1.1
MTU = 1420

[Peer]
PublicKey = <hub-public-key>
Endpoint = hub.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
PresharedKey = <auto-generated>
```

### Cấu hình Client trên Hub

Trong `config.py` hoặc `.env`:

```bash
# Client Device Settings
CLIENT_IP_POOL_START=100     # Bắt đầu từ .100
CLIENT_IP_POOL_END=250       # Kết thúc ở .250 (150 clients max)
CLIENT_DEFAULT_EXPIRES_DAYS=30
CLIENT_MAX_DEVICES_PER_USER=5
CLIENT_REQUIRE_ADMIN_APPROVAL=false
```

### Security Notes

1. **Config Token**: Là mật khẩu một lần để download config. Có thể cấu hình để xóa sau lần download đầu.

2. **Private Key**: Được sinh và lưu trên server (encrypted). Khi user download config, private key được gửi qua HTTPS.

3. **Expiration**: Mỗi client config có thời hạn. Sau khi hết hạn, cần tạo device mới.

4. **Revocation**: Admin có thể revoke device bất cứ lúc nào. Peer sẽ bị xóa khỏi Hub WireGuard.

5. **NAT Masquerade**: Hub server đã cấu hình NAT để forward traffic từ clients ra internet.

---

Đây là **hệ thống Zero Trust hoàn chỉnh**, implement đầy đủ các nguyên tắc NIST SP 800-207 với khả năng mở rộng và maintain dễ dàng.