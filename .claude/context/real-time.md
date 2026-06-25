# Real-time — Pusher

Vedi anche: [inbox.md](./inbox.md), [widget.md](./widget.md).

## Stack

- **Provider:** Pusher (hosted WebSocket service)
- **Server SDK:** `pusher` npm package
- **Client SDK:** `pusher-js`
- **Server file:** `lib/pusher-server.ts`
- **Client file:** `lib/pusher-client.ts`

## Variabili d'ambiente

```bash
PUSHER_APP_ID=               # server-side
PUSHER_SECRET=               # server-side
NEXT_PUBLIC_PUSHER_KEY=      # client-side
NEXT_PUBLIC_PUSHER_CLUSTER=  # client-side (es. "eu")
```

## Istanza server

```typescript
// lib/pusher-server.ts
function getPusherServer(): Pusher | null
// Ritorna null se PUSHER_APP_ID/SECRET non configurati

// Utilizzo
const pusher = getPusherServer()
if (pusher) {
  await pusher.trigger(channelName, eventName, data)
}
```

## Istanza client

```typescript
// lib/pusher-client.ts
function getPusherClient(): PusherJS | null
// Singleton, inizializzato con NEXT_PUBLIC_PUSHER_KEY

// Utilizzo nei componenti React
const pusher = getPusherClient()
const channel = pusher.subscribe("private-conversation-xxx")
channel.bind("message:created", handler)
```

## Canali

| Canale | Tipo | Usato da | Scopo |
|---|---|---|---|
| `private-conversation-{id}` | Private | Agenti + Widget | Messaggi in una conversazione |
| `private-workspace-{id}` | Private | Agenti nel dashboard | Nuove conversazioni, aggiornamenti |
| `presence-visitor-{id}` | Presence | Widget + Agenti | Status online visitatore |

### Canali privati

Richiedono autenticazione tramite `POST /api/pusher/auth`. Il server verifica che l'utente abbia accesso al canale richiesto (es. sia membro del workspace o sia il visitatore della conversazione).

## Eventi

### `private-conversation-{id}`

| Evento | Payload | Emesso da |
|---|---|---|
| `message:created` | `{ message: Message }` | `sendMessage()` action, widget API |
| `conversation:updated` | `{ conversation: Conversation }` | varie actions |

### `private-workspace-{id}`

| Evento | Payload | Emesso da |
|---|---|---|
| `conversation:new-message` | `{ conversationId, preview }` | widget message API |
| `conversation:created` | `{ conversation: Conversation }` | widget conversation API |
| `conversation:assigned` | `{ conversationId, assigneeId }` | `assignConversation()` |

### `presence-visitor-{id}`

Canale di presenza per tracciare quando il visitatore è online/offline nella chat widget.

## Autenticazione canali privati

```typescript
// app/api/pusher/auth/route.ts
POST /api/pusher/auth
Body: { socket_id, channel_name }

// Verifica:
// - Per "private-conversation-*": utente è membro del workspace
// - Per "private-workspace-*": utente è membro del workspace
// - Per "presence-visitor-*": token visitatore valido

// Response: { auth: "pusher:signature" }
```

## Pattern di sottoscrizione nel dashboard

```typescript
// components/inbox/conversation-list.tsx o simile
useEffect(() => {
  const pusher = getPusherClient()
  if (!pusher) return

  const channel = pusher.subscribe(`private-workspace-${workspaceId}`)
  channel.bind("conversation:new-message", (data) => {
    // aggiorna lista conversazioni
  })

  return () => {
    channel.unsubscribe()
  }
}, [workspaceId])
```

## Pattern di sottoscrizione nel widget

Il widget Preact gestisce la sottoscrizione ai canali dentro `packages/widget/src/`. Usa `presence-visitor-{id}` per ricevere risposte degli agenti.

## Fallback senza Pusher

Se `PUSHER_APP_ID` non è configurato, `getPusherServer()` ritorna `null` e le chiamate a Pusher vengono silenziosamente saltate. L'app funziona ma senza aggiornamenti real-time (richiede refresh manuale).
