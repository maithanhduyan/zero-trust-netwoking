# Zero Trust Network Dashboard

Giao diện web quản lý Zero Trust Network Control Plane, hiển thị network topology với Sigma.js và quản lý nodes, users, policies.

## 📸 Screenshot

```
┌───────────────────────────────────────────────────────────────────────┐
│  Zero Trust Network                    Dashboard | Nodes | Policies  │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌─────────────────────────────────┐  ┌───────────────────────────┐  │
│   │                                 │  │  Metrics                  │  │
│   │      ○ hub-main                 │  │  • Total Nodes: 4         │  │
│   │        ╱   ╲                    │  │  • Active: 4              │  │
│   │       ╱     ╲                   │  │  • Pending: 0             │  │
│   │  ○ app-01   ○ db-primary        │  │  • Policies: 12           │  │
│   │       ╲     ╱                   │  └───────────────────────────┘  │
│   │        ╲   ╱                    │                                 │
│   │       ○ ops-admin               │  ┌───────────────────────────┐  │
│   │                                 │  │  Node Details             │  │
│   │      Network Graph (Sigma.js)   │  │  • Hostname: hub-main     │  │
│   │                                 │  │  • Role: hub              │  │
│   └─────────────────────────────────┘  │  • IP: 10.10.0.2/24       │  │
│                                        │  • Status: active         │  │
│                                        │  [Approve] [Suspend]      │  │
│                                        └───────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

## ✨ Features

- **Network Topology Graph**: Trực quan hóa mạng với Sigma.js và Graphology
  - Hub-centric radial layout
  - Node colors theo role (hub, app, db, ops, gateway, monitor)
  - Edge colors theo status (active=green, pending=yellow)
  - Click để xem chi tiết node

- **Real-time Updates**: WebSocket connection cho live updates
  - Node registration events
  - Trust score changes
  - Policy updates

- **Node Management**: Quản lý nodes từ dashboard
  - Approve pending nodes
  - Suspend/Revoke active nodes
  - View node details và metrics

- **Multi-page Navigation**:
  - `/` - Dashboard với network graph
  - `/nodes` - Danh sách tất cả nodes
  - `/clients` - Client devices management
  - `/users` - User management
  - `/policies` - Access policies
  - `/events` - Event log

## 🛠 Tech Stack

| Technology | Purpose |
|------------|---------|
| **React 18** | UI Framework |
| **TypeScript** | Type safety |
| **Vite 6** | Build tool & dev server |
| **TailwindCSS 3** | Styling |
| **Sigma.js 3** | Graph visualization |
| **Graphology** | Graph data structure |
| **@tanstack/react-query** | Data fetching & caching |
| **react-router-dom 7** | Client-side routing |
| **Axios** | HTTP client |
| **Lucide React** | Icons |

## 📋 Prerequisites

- Node.js >= 18
- npm >= 9
- Control Plane API running on port 8000

## 🚀 Quick Start

### 1. Install dependencies

```bash
cd web-ui
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
```env
# API URL (proxied through Vite)
VITE_API_URL=/api/v1

# Admin Token - MUST match ADMIN_SECRET from Control Plane
VITE_ADMIN_TOKEN=change-me-admin-secret
```

### 3. Start Control Plane (if not running)

```bash
cd ../control-plane
uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 4. Start Dashboard

```bash
npm run dev
```

Open http://localhost:3000

## 📁 Project Structure

```
web-ui/
├── index.html          # HTML entry point
├── package.json        # Dependencies
├── vite.config.ts      # Vite config with proxy
├── tsconfig.json       # TypeScript config
├── tailwind.config.js  # TailwindCSS theme
├── postcss.config.js   # PostCSS config
├── .env                # Environment variables
├── .env.example        # Example env file
└── src/
    ├── main.tsx        # React entry point
    ├── App.tsx         # App with routing
    ├── index.css       # TailwindCSS imports
    ├── vite-env.d.ts   # Vite env types
    ├── types/
    │   └── api.ts      # TypeScript interfaces
    ├── lib/
    │   └── api.ts      # Axios API client
    ├── components/
    │   ├── Layout.tsx          # App layout with sidebar
    │   ├── NetworkGraph.tsx    # Sigma.js graph component
    │   ├── NodeDetailsPanel.tsx # Node details sidebar
    │   ├── MetricsCards.tsx    # Stats cards
    │   └── GraphControls.tsx   # Graph zoom/fit controls
    ├── pages/
    │   ├── DashboardPage.tsx   # Main dashboard
    │   ├── NodesPage.tsx       # Nodes list
    │   ├── ClientsPage.tsx     # Client devices
    │   ├── UsersPage.tsx       # User management
    │   ├── PoliciesPage.tsx    # Access policies
    │   └── EventsPage.tsx      # Event log
    └── hooks/
        └── useWebSocket.ts     # Real-time WebSocket hook
```

## 🎨 Customization

### Theme Colors

Edit `tailwind.config.js`:

```javascript
colors: {
    'zt-primary': '#3b82f6',     // Blue accent
    'zt-dark': '#1e293b',        // Dark background
    'zt-darker': '#0f172a',      // Darker background
}
```

### Node Role Colors

Edit `src/components/NetworkGraph.tsx`:

```typescript
const ROLE_COLORS: Record<string, string> = {
    hub: '#3b82f6',      // Blue
    app: '#22c55e',      // Green
    db: '#f97316',       // Orange
    ops: '#a855f7',      // Purple
    gateway: '#06b6d4',  // Cyan
    monitor: '#eab308',  // Yellow
    client: '#94a3b8',   // Gray
}
```

## 🔧 VSCode Tasks

Workspace đã có `.vscode/tasks.json` với các tasks:

| Task | Description |
|------|-------------|
| `Kill Port 3000` | Kill process on port 3000 |
| `Kill Port 8000` | Kill process on port 8000 |
| `Kill Both Ports` | Kill both ports |
| `Start Control Plane` | Run Control Plane with uv |
| `Start Dashboard` | Run Dashboard dev server |

Run with: `Ctrl+Shift+P` → `Tasks: Run Task`

## 🔌 API Endpoints Used

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/admin/nodes` | GET | List all nodes |
| `/api/v1/admin/nodes/{id}` | GET | Get node details |
| `/api/v1/admin/nodes/{id}/approve` | POST | Approve node |
| `/api/v1/admin/nodes/{id}/suspend` | POST | Suspend node |
| `/api/v1/admin/nodes/{id}/revoke` | POST | Revoke node |
| `/api/v1/client/devices` | GET | List client devices |
| `/api/v1/users` | GET | List users |
| `/api/v1/groups` | GET | List groups |
| `/api/v1/policies` | GET | List policies |
| `/api/v1/events` | GET | List events |

## 🌐 WebSocket Events

```typescript
// Connection
ws://localhost:8000/api/v1/ws?admin_token=YOUR_TOKEN

// Events received
interface WebSocketEvent {
    event_type: string  // NodeRegistered, TrustScoreChanged, etc.
    data: any
    timestamp: string
}
```

## 📝 Scripts

```bash
npm run dev      # Start dev server (port 3000)
npm run build    # Build for production
npm run preview  # Preview production build
npm run lint     # Run ESLint
```

## 🐛 Troubleshooting

### 1. API 401 Unauthorized
```bash
# Check ADMIN_TOKEN matches ADMIN_SECRET in Control Plane
grep ADMIN_SECRET ../control-plane/.env.example
```

### 2. Proxy not working
```bash
# Check Control Plane is running
curl http://localhost:8000/health
```

### 3. Graph not displaying
- Check browser console for errors
- Verify nodes exist: `curl http://localhost:3000/api/v1/admin/nodes`

### 4. WebSocket not connecting
- WebSocket URL uses ws:// not http://
- Check `useWebSocket` hook console logs

## 📄 License

MIT License - See LICENSE file

## 🔗 Related

- [Control Plane](../control-plane/README.md)
- [Agent](../agent/README.md)
- [Documentation](../docs/README.MD)
