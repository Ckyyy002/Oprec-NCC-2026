# 🔌 WebSocket — Komunikasi Real-Time

## Apa itu WebSocket?

WebSocket adalah protokol komunikasi yang menyediakan **full-duplex**, **persistent connection** antara client dan server melalui satu TCP connection. Berbeda dengan HTTP yang bersifat request-response (half-duplex), WebSocket memungkinkan server mengirim data ke client kapan saja tanpa harus menunggu request.

---

## HTTP vs WebSocket

| Aspek | HTTP | WebSocket |
|---|---|---|
| Connection | Buka-tutup per request | Persistent (satu koneksi) |
| Komunikasi | Half-duplex (request → response) | Full-duplex (dua arah bebas) |
| Overhead | Header besar per request | Header kecil setelah handshake |
| Inisiasi push | Tidak bisa (harus polling) | Server bisa push kapan saja |
| Use case | REST API, halaman web | Chat, live dashboard, game |

---

## Cara Kerja WebSocket

```
Client                          Server
  │                               │
  │── HTTP GET /ws ──────────────►│
  │   Upgrade: websocket          │
  │   Connection: Upgrade         │
  │                               │
  │◄─ 101 Switching Protocols ───│
  │   Upgrade: websocket          │
  │                               │
  │════════ WS Connection ════════│  ← Handshake selesai
  │                               │
  │── Message: "Hello" ──────────►│
  │◄─ Message: "Hi back!" ───────│
  │◄─ Push: "New notification" ──│  ← Server push tanpa diminta
  │                               │
  │── Close Frame ───────────────►│
  │◄─ Close Frame ────────────────│
  │                               │
  │════════ Connection Closed ════│
```

---

## WebSocket API (Browser)

### Client-side (JavaScript)

```javascript
// Buka koneksi
const ws = new WebSocket('ws://localhost:3000/ws');
// Untuk TLS: wss://domain.com/ws

// Event: koneksi terbuka
ws.addEventListener('open', () => {
    console.log('✅ WebSocket connected');

    // Kirim pesan
    ws.send(JSON.stringify({
        type: 'SUBSCRIBE',
        channel: 'notifications'
    }));
});

// Event: menerima pesan
ws.addEventListener('message', (event) => {
    const data = JSON.parse(event.data);
    console.log('📨 Received:', data);

    switch (data.type) {
        case 'NOTIFICATION':
            showNotification(data.payload);
            break;
        case 'UPDATE':
            updateDashboard(data.payload);
            break;
    }
});

// Event: error
ws.addEventListener('error', (error) => {
    console.error('❌ WebSocket error:', error);
});

// Event: koneksi tertutup
ws.addEventListener('close', (event) => {
    console.log(`Connection closed: code=${event.code} reason=${event.reason}`);
    // Auto-reconnect
    setTimeout(() => reconnect(), 3000);
});

// Kirim pesan
function sendMessage(message) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(message));
    }
}

// Tutup koneksi
function disconnect() {
    ws.close(1000, 'User logout');
}
```

### WebSocket Ready States

| State | Nilai | Deskripsi |
|---|---|---|
| `CONNECTING` | 0 | Sedang melakukan handshake |
| `OPEN` | 1 | Koneksi aktif, siap kirim/terima |
| `CLOSING` | 2 | Proses penutupan koneksi |
| `CLOSED` | 3 | Koneksi sudah tertutup |

---

## Server-side Implementation

### Node.js dengan `ws`

```typescript
import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Map untuk track semua client
const clients = new Map<string, WebSocket>();

wss.on('connection', (ws: WebSocket, req) => {
    const clientId = generateId();
    clients.set(clientId, ws);

    console.log(`✅ Client connected: ${clientId} (total: ${clients.size})`);

    // Kirim pesan selamat datang
    ws.send(JSON.stringify({
        type: 'CONNECTED',
        clientId,
        timestamp: new Date().toISOString()
    }));

    // Terima pesan dari client
    ws.on('message', (raw) => {
        try {
            const message = JSON.parse(raw.toString());
            handleMessage(ws, clientId, message);
        } catch (err) {
            ws.send(JSON.stringify({ type: 'ERROR', message: 'Invalid JSON' }));
        }
    });

    // Heartbeat untuk deteksi koneksi mati
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    // Handle disconnect
    ws.on('close', (code, reason) => {
        clients.delete(clientId);
        console.log(`❌ Client disconnected: ${clientId} (code: ${code})`);
    });

    ws.on('error', (err) => {
        console.error(`Error on ${clientId}:`, err);
        clients.delete(clientId);
    });
});

// Heartbeat interval — deteksi zombie connections
const heartbeat = setInterval(() => {
    wss.clients.forEach((ws: any) => {
        if (!ws.isAlive) return ws.terminate();
        ws.isAlive = false;
        ws.ping();
    });
}, 30_000);

wss.on('close', () => clearInterval(heartbeat));

// Message handler
function handleMessage(ws: WebSocket, clientId: string, message: any) {
    switch (message.type) {
        case 'CHAT':
            broadcast({ type: 'CHAT', from: clientId, text: message.text });
            break;
        case 'PING':
            ws.send(JSON.stringify({ type: 'PONG' }));
            break;
        default:
            ws.send(JSON.stringify({ type: 'ERROR', message: 'Unknown message type' }));
    }
}

// Broadcast ke semua client
function broadcast(data: object, exclude?: string) {
    const payload = JSON.stringify(data);
    clients.forEach((client, id) => {
        if (id !== exclude && client.readyState === WebSocket.OPEN) {
            client.send(payload);
        }
    });
}

server.listen(3000, () => console.log('Server running on port 3000'));
```

---

### Go (Gorilla WebSocket)

```go
package main

import (
    "encoding/json"
    "log"
    "net/http"
    "sync"

    "github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
    CheckOrigin: func(r *http.Request) bool {
        return true // Ganti dengan validasi origin di production
    },
}

type Hub struct {
    clients    map[*websocket.Conn]bool
    broadcast  chan []byte
    register   chan *websocket.Conn
    unregister chan *websocket.Conn
    mu         sync.RWMutex
}

func NewHub() *Hub {
    return &Hub{
        clients:    make(map[*websocket.Conn]bool),
        broadcast:  make(chan []byte),
        register:   make(chan *websocket.Conn),
        unregister: make(chan *websocket.Conn),
    }
}

func (h *Hub) Run() {
    for {
        select {
        case conn := <-h.register:
            h.mu.Lock()
            h.clients[conn] = true
            h.mu.Unlock()

        case conn := <-h.unregister:
            h.mu.Lock()
            if _, ok := h.clients[conn]; ok {
                delete(h.clients, conn)
                conn.Close()
            }
            h.mu.Unlock()

        case message := <-h.broadcast:
            h.mu.RLock()
            for conn := range h.clients {
                if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
                    conn.Close()
                    delete(h.clients, conn)
                }
            }
            h.mu.RUnlock()
        }
    }
}

func wsHandler(hub *Hub, w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Println("Upgrade error:", err)
        return
    }
    hub.register <- conn

    defer func() {
        hub.unregister <- conn
    }()

    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            break
        }
        hub.broadcast <- msg
    }
}
```

---

## Rooms & Namespaces (Socket.IO)

```typescript
import { Server } from 'socket.io';

const io = new Server(httpServer, {
    cors: { origin: '*' }
});

io.on('connection', (socket) => {

    // Join room
    socket.on('join_room', (room: string) => {
        socket.join(room);
        socket.to(room).emit('user_joined', { id: socket.id });
    });

    // Kirim ke room tertentu
    socket.on('room_message', ({ room, message }) => {
        io.to(room).emit('new_message', {
            from: socket.id,
            message,
            timestamp: Date.now()
        });
    });

    // Leave room
    socket.on('leave_room', (room: string) => {
        socket.leave(room);
        socket.to(room).emit('user_left', { id: socket.id });
    });

    socket.on('disconnect', () => {
        console.log('User disconnected:', socket.id);
    });
});
```

---

## Auto-Reconnect dengan Exponential Backoff

```typescript
class ReconnectingWebSocket {
    private ws: WebSocket | null = null;
    private reconnectAttempts = 0;
    private maxReconnectAttempts = 10;
    private baseDelay = 1000; // 1 detik

    constructor(private url: string) {
        this.connect();
    }

    private connect() {
        this.ws = new WebSocket(this.url);

        this.ws.onopen = () => {
            console.log('✅ Connected');
            this.reconnectAttempts = 0;
        };

        this.ws.onclose = () => {
            this.scheduleReconnect();
        };

        this.ws.onerror = (err) => {
            console.error('WebSocket error:', err);
        };
    }

    private scheduleReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.error('Max reconnect attempts reached');
            return;
        }

        // Exponential backoff dengan jitter
        const delay = Math.min(
            this.baseDelay * Math.pow(2, this.reconnectAttempts),
            30_000 // max 30 detik
        ) + Math.random() * 1000;

        console.log(`🔄 Reconnecting in ${Math.round(delay)}ms... (attempt ${this.reconnectAttempts + 1})`);
        this.reconnectAttempts++;
        setTimeout(() => this.connect(), delay);
    }

    send(data: object) {
        if (this.ws?.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(data));
        }
    }
}
```

---

## WebSocket di Balik Nginx (Reverse Proxy)

```nginx
upstream websocket_backend {
    server app:3000;
}

server {
    listen 80;
    server_name example.com;

    location /ws {
        proxy_pass http://websocket_backend;
        proxy_http_version 1.1;

        # Header wajib untuk upgrade WebSocket
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # Timeout lebih lama untuk koneksi persistent
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

---

## Use Cases

| Use Case | Deskripsi |
|---|---|
| **Live Chat** | Messaging antar pengguna secara real-time |
| **Live Dashboard** | Monitoring metrik yang update otomatis |
| **Collaborative Editing** | Google Docs-like real-time editing |
| **Online Gaming** | State game yang sync antara pemain |
| **Trading Platform** | Update harga saham/kripto secara live |
| **Notifikasi Real-time** | Push notifikasi tanpa polling |
| **IoT Dashboard** | Data sensor yang streaming dari device |

---

## Best Practices

### 1. Message Protocol yang Konsisten
```json
{
    "type": "EVENT_NAME",
    "payload": {},
    "timestamp": 1700000000000,
    "id": "unique-message-id"
}
```

### 2. Authentication
```typescript
// Kirim token saat connection
const ws = new WebSocket(`ws://server/ws?token=${authToken}`);

// Atau validasi di server via header (tidak semua browser support)
ws.on('connection', (socket, req) => {
    const token = new URLSearchParams(req.url.split('?')[1]).get('token');
    if (!validateToken(token)) socket.close(1008, 'Unauthorized');
});
```

### 3. Batasi Message Rate (Rate Limiting)
```typescript
const rateLimiter = new Map<string, number>();

ws.on('message', (raw) => {
    const now = Date.now();
    const lastMsg = rateLimiter.get(clientId) ?? 0;
    if (now - lastMsg < 100) { // max 10 msg/detik
        ws.send(JSON.stringify({ type: 'RATE_LIMITED' }));
        return;
    }
    rateLimiter.set(clientId, now);
    // proses pesan...
});
```

---

## Troubleshooting

| Masalah | Solusi |
|---|---|
| 101 tidak muncul | Cek header Upgrade di Nginx, pastikan `proxy_http_version 1.1` |
| Koneksi sering drop | Implementasi heartbeat (ping/pong) |
| Memory leak di server | Pastikan semua listener di-cleanup saat disconnect |
| CORS error | Set `CheckOrigin` / `cors` di server side |
| Pesan hilang saat reconnect | Implementasi message queue / acknowledgment |

---

## Referensi

- [MDN WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
- [RFC 6455 — WebSocket Protocol](https://datatracker.ietf.org/doc/html/rfc6455)
- [Socket.IO Docs](https://socket.io/docs/)
- [Gorilla WebSocket (Go)](https://pkg.go.dev/github.com/gorilla/websocket)
- [ws Library (Node.js)](https://github.com/websockets/ws)
