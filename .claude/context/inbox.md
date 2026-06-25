# Inbox — Conversazioni e Messaggi

Vedi anche: [database.md](./database.md), [real-time.md](./real-time.md), [ai.md](./ai.md).

## Panoramica

L'inbox è il cuore dell'app: gestisce le conversazioni tra visitatori (via widget) e agenti (nel dashboard). Le conversazioni possono essere assegnate, taggete, snoozate e analizzate con AI.

## Struttura Route

```
app/(protected)/workspace/[workspaceSlug]/inbox/
├── page.tsx              → Lista conversazioni (default: OPEN)
├── [conversationId]/
│   └── page.tsx          → Dettaglio conversazione
```

## Componenti principali

Tutti in `components/inbox/`:

| Componente | File | Descrizione |
|---|---|---|
| InboxLayout | `inbox-layout.tsx` | Split: lista sx + dettaglio dx |
| ConversationList | `conversation-list.tsx` | Lista con filtri e paginazione |
| ConversationListItem | `conversation-list-item.tsx` | Preview singola conversazione |
| ConversationDetailSidebar | `conversation-detail-sidebar.tsx` | Pannello info visitatore + azioni |
| MessageThread | `message-thread.tsx` | Thread messaggi completo |
| MessageBubble | `message-bubble.tsx` | Singolo messaggio (bubble UI) |
| ReplyBox | `reply-box.tsx` | Input agente con tab Reply/Note |
| ConversationFilters | `conversation-filters.tsx` | Filtri status, assegnatario, tag |
| CannedResponsePicker | `canned-response-picker.tsx` | Selezione template risposta |

## Tipi di messaggio (MessageType)

| Tipo | Chi lo invia | Visibilità |
|---|---|---|
| `VISITOR` | Visitatore via widget | Agenti + visitatore |
| `AGENT` | Agente dal dashboard | Agenti + visitatore |
| `NOTE` | Agente (nota interna) | Solo agenti |
| `SYSTEM` | Sistema (eventi automatici) | Solo agenti |
| `BOT` | Sistema AI/bot | Agenti + visitatore |

## Status conversazione (ConversationStatus)

- `OPEN` — attiva
- `SNOOZED` — silenziata fino a `snoozedUntil` datetime
- `CLOSED` — chiusa

## Server Actions principali

Tutte in `actions/`:

```typescript
// Invia messaggio (agente o nota interna)
sendMessage(conversationId, body, type: "AGENT" | "NOTE", attachments?)
// → salva Message in DB
// → emette evento Pusher "message:created"
// → notifica email se primo messaggio agente

// Assegna conversazione a membro
assignConversation(conversationId, assigneeId)

// Cambia status
updateConversationStatus(conversationId, status: ConversationStatus)

// Gestione tag
tagConversation(conversationId, tags: string[])

// Operazioni bulk (close, assign, etc.)
bulkConversationActions(conversationIds, action, params)
```

## API Routes

```
GET  /api/inbox/conversations?workspaceId=xxx&status=OPEN&assigneeId=xxx
POST /api/inbox/conversations/[id]/messages   → send agent message
```

## Flusso messaggio visitatore → agente

1. Widget invia `POST /api/widget/conversations/[id]/messages`
2. API route: salva `Message` (type: `VISITOR`)
3. Trigger Pusher channel `private-workspace-{id}` → evento `conversation:new-message`
4. Dashboard aggiorna lista conversazioni real-time
5. Se conversazione ha un assegnatario → invia email notification

## Flusso risposta agente

1. Agente scrive nel `ReplyBox` e invia
2. `sendMessage()` action:
   - Salva `Message` (type: `AGENT` o `NOTE`)
   - Emette Pusher event `message:created` su `private-conversation-{id}`
3. Widget visitatore riceve evento e mostra il messaggio

## AI Features integrate

Accessibili dalla sidebar della conversazione:

- **Suggest reply** — suggerisce risposta basata sul thread
- **Summarize** — genera riassunto della conversazione (salvato in `aiSummary`)
- **Categorize** — suggerisce tag/categoria
- **Sentiment** — analizza tono del visitatore
- **Suggest articles** — articoli KB correlati

Vedi [ai.md](./ai.md) per dettagli implementativi.

## Assegnazione e notifiche

- `assigneeId` → riferisce a `WorkspaceMember`
- Email di notifica inviata all'agente assegnato via `sendAgentNotificationEmail()`
- Reply-to email: `reply+{conversationId}@mail.guddesk.com` (inbound email handling)

## Filtri disponibili

- Status: OPEN / SNOOZED / CLOSED
- Assegnatario: me / altri / non assegnate
- Tag
- Testo libero (search)

## Real-time (Pusher channels)

Vedi [real-time.md](./real-time.md).

Canali rilevanti per l'inbox:
- `private-workspace-{workspaceId}` → nuove conversazioni
- `private-conversation-{conversationId}` → messaggi nella conversazione
