# API Routes

Vedi anche: [widget.md](./widget.md), [real-time.md](./real-time.md).

## Struttura

```
app/api/
├── auth/[...nextauth]/    → NextAuth handlers
├── widget/                → Widget public API
│   ├── config/            → GET: config widget
│   ├── auth/              → POST: token visitatore
│   ├── visitors/          → GET/POST: gestione visitor
│   ├── conversations/     → GET/POST: conversazioni
│   │   └── [id]/
│   │       └── messages/  → GET/POST: messaggi
│   └── articles/
│       └── search/        → GET: ricerca KB
├── inbox/
│   └── conversations/
│       └── [id]/
│           └── messages/  → POST: messaggio agente
├── pusher/
│   └── auth/              → POST: auth canali privati
├── user/                  → DELETE: elimina account
├── email/
│   └── inbound/           → POST: webhook email inbound
└── cron/
    └── analytics/         → POST: snapshot analytics giornaliero
```

---

## Widget API (`/api/widget/`)

Tutte le route del widget sono pubbliche (no auth sessione) ma richiedono un `appId` valido o un token visitatore.

### GET `/api/widget/config`
**Query:** `?appId=xxx`
**Response:**
```json
{
  "primaryColor": "#000",
  "position": "bottom-right",
  "welcomeMessage": "Ciao! Come possiamo aiutarti?",
  "requireEmail": false,
  "workspaceId": "xxx",
  "helpCenterEnabled": true
}
```

### POST `/api/widget/auth`
**Body:**
```json
{ "appId": "xxx", "visitorId": "optional-visitor-id" }
```
**Response:**
```json
{ "token": "jwt-visitor-token", "visitorId": "xxx" }
```

### GET `/api/widget/visitors`
**Headers:** `Authorization: Bearer visitor-token`
**Response:** Dati del visitatore corrente

### POST `/api/widget/visitors`
**Headers:** `Authorization: Bearer visitor-token`
**Body:**
```json
{
  "externalId": "user-123",
  "name": "Mario",
  "email": "mario@example.com",
  "metadata": {}
}
```

### GET `/api/widget/conversations`
**Headers:** `Authorization: Bearer visitor-token`
**Response:** Array conversazioni del visitatore

### POST `/api/widget/conversations`
**Headers:** `Authorization: Bearer visitor-token`
**Body:** `{ "subject": "optional" }`
**Response:** Nuova `Conversation`

### GET `/api/widget/conversations/[id]/messages`
**Headers:** `Authorization: Bearer visitor-token`
**Response:** Array messaggi (escluse NOTE interne)

### POST `/api/widget/conversations/[id]/messages`
**Headers:** `Authorization: Bearer visitor-token`
**Body:** `{ "body": "testo messaggio" }`
**Side effects:**
- Salva `Message` (type: VISITOR)
- Emette Pusher `private-workspace-{id}` → `conversation:new-message`
- Esegue automazioni
- Invia email agente (se assegnato)

### GET `/api/widget/articles/search`
**Query:** `?q=testo&workspaceId=xxx`
**Response:** Array articoli pubblicati rilevanti

---

## Auth API

### NextAuth handler (`/api/auth/[...nextauth]`)
Gestito da NextAuth. Endpoints gestiti automaticamente:
- `GET/POST /api/auth/signin`
- `GET/POST /api/auth/signout`
- `GET /api/auth/session`
- `GET /api/auth/csrf`
- `GET /api/auth/providers`
- `POST /api/auth/callback/[provider]`

---

## Inbox API

### POST `/api/inbox/conversations/[id]/messages`
**Auth:** Sessione NextAuth (workspace member)
**Body:** `{ "body": "testo", "type": "AGENT" | "NOTE" }`
**Side effects:**
- Salva `Message`
- Emette Pusher `private-conversation-{id}` → `message:created`

---

## Pusher Auth

### POST `/api/pusher/auth`
**Auth:** Sessione NextAuth o token visitatore
**Body:** `{ "socket_id": "xxx", "channel_name": "private-xxx" }`
**Logica:** verifica accesso al canale e ritorna firma Pusher

---

## User API

### DELETE `/api/user`
**Auth:** Sessione NextAuth
**Side effects:** elimina account utente e tutti i dati associati

---

## Email Webhook

### POST `/api/email/inbound`
**Auth:** nessuna (webhook esterno da Resend/Postmark)
**Body:** formato email inbound del provider
**Logica:** parsea il `conversationId` dal header Reply-To, crea messaggio AGENT

---

## Cron Job

### POST `/api/cron/analytics`
**Auth:** header `Authorization: Bearer CRON_SECRET`
**Logica:** crea `AnalyticsSnapshot` con metriche del giorno precedente per ogni workspace
**Scheduling:** deve essere chiamato quotidianamente (es. tramite Vercel Cron, crontab, o servizio esterno)

---

## Convenzioni

- Tutti gli endpoint ritornano JSON
- Errori: `{ error: "messaggio" }` con status HTTP appropriato
- Autenticazione mista: sessione NextAuth per agenti, JWT visitatore per widget
- Nessuna autenticazione sulle route widget (usano solo `appId` o token)
