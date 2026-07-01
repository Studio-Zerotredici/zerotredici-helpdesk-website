# Real-time — Pusher / Soketi self-hosted

Vedi anche: [inbox.md](./inbox.md), [widget.md](./widget.md).

## Stack

Due backend supportati, scelti a runtime in base alle env var (nessuna
modifica di codice richiesta per passare dall'uno all'altro):

- **Opzione A — Pusher Cloud:** servizio SaaS hosted. I dati di chat
  escono dalla nostra infrastruttura.
- **Opzione B — Soketi self-hosted:** server Pusher-protocol-compatible,
  auto-ospitato (scelto per Studio Zerotredici su Dokploy per data
  residency EU — vedi [`DOKPLOY.md`](../../DOKPLOY.md) step 2). Quando
  `PUSHER_HOST` (server) / `NEXT_PUBLIC_PUSHER_HOST` (client) sono
  impostati, hanno priorità sul cluster Pusher Cloud.

- **Server SDK:** `pusher` npm package
- **Client SDK:** `pusher-js`
- **Server file:** `lib/pusher-server.ts`
- **Client file:** `lib/pusher-client.ts`
- **Widget:** `packages/widget/src/api/pusher.ts` (stessa logica, bundle separato)

## Variabili d'ambiente

```bash
# Comuni
PUSHER_APP_ID=                    # server-side
PUSHER_SECRET=                    # server-side
NEXT_PUBLIC_PUSHER_KEY=           # client-side

# Opzione A — Pusher Cloud
NEXT_PUBLIC_PUSHER_CLUSTER=       # es. "eu"

# Opzione B — Soketi self-hosted (PUSHER_HOST presente > cluster)
PUSHER_HOST=                      # es. ws.yourdomain.com
PUSHER_PORT=                      # default 6001, es. 443 dietro TLS
PUSHER_USE_TLS=                   # "true"/"false"
NEXT_PUBLIC_PUSHER_HOST=
NEXT_PUBLIC_PUSHER_PORT=
NEXT_PUBLIC_PUSHER_FORCE_TLS=
```

Con Soketi, `PUSHER_APP_ID` / `NEXT_PUBLIC_PUSHER_KEY` / `PUSHER_SECRET`
devono combaciare esattamente con `SOKETI_DEFAULT_APP_ID` /
`_APP_KEY` / `_APP_SECRET` configurati sul servizio Soketi.

## Istanza server

```typescript
// lib/pusher-server.ts
function getPusherServer(): Pusher | null
// Ritorna null se PUSHER_APP_ID/SECRET non configurati, oppure se né
// PUSHER_HOST né NEXT_PUBLIC_PUSHER_CLUSTER sono impostati

// Se PUSHER_HOST è settato: new Pusher({ appId, key, secret, host, port, useTLS })
// Altrimenti (Pusher Cloud): new Pusher({ appId, key, secret, cluster, useTLS: true })

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

// Se NEXT_PUBLIC_PUSHER_HOST è settato: new PusherClient(key, { wsHost, wsPort, wssPort, forceTLS, ... })
// Altrimenti (Pusher Cloud): new PusherClient(key, { cluster, ... })

// Utilizzo nei componenti React
const pusher = getPusherClient()
const channel = pusher.subscribe("private-conversation-xxx")
channel.bind("message:created", handler)
```

**Nota tipizzazione:** `pusher-js` tipizza `cluster` come campo obbligatorio
in `Options` anche quando si usa `wsHost` (dove viene ignorato a runtime).
Sia `lib/pusher-client.ts` che `packages/widget/src/api/pusher.ts` passano
un `cluster: ""` placeholder nel branch `wsHost` per soddisfare TypeScript
senza cambiare il comportamento a runtime.

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
