# Automazioni

Vedi anche: [database.md](./database.md), [inbox.md](./inbox.md).

## Panoramica

Le automazioni permettono di eseguire azioni automatiche basate su trigger e condizioni. Ogni workspace ha le sue regole di automazione indipendenti.

## Struttura Route

```
app/(protected)/workspace/[workspaceSlug]/automations/
├── page.tsx              → Lista regole di automazione
└── [automationId]/
    └── page.tsx          → Editor regola
```

## Modello DB

```prisma
model AutomationRule {
  id           String            @id @default(cuid())
  name         String
  trigger      AutomationTrigger
  conditions   Json              // Array<Condition>
  action       AutomationAction
  actionConfig Json              // parametri specifici dell'azione
  isEnabled    Boolean           @default(true)
  workspaceId  String
}
```

## Trigger disponibili (AutomationTrigger)

| Trigger | Quando si attiva |
|---|---|
| `CONVERSATION_CREATED` | Nuova conversazione creata |
| `MESSAGE_RECEIVED` | Nuovo messaggio da visitatore |
| `TAG_ADDED` | Tag aggiunto alla conversazione |
| `CONVERSATION_ASSIGNED` | Conversazione assegnata a un agente |
| `STATUS_CHANGED` | Status della conversazione cambiato |

## Azioni disponibili (AutomationAction)

| Azione | Cosa fa | actionConfig |
|---|---|---|
| `ASSIGN_TO` | Assegna a un agente | `{ memberId: string }` |
| `ADD_TAG` | Aggiunge tag | `{ tag: string }` |
| `SEND_MESSAGE` | Invia messaggio BOT | `{ body: string }` |
| `NOTIFY_SLACK` | Notifica canale Slack | `{ channelId: string }` |

## Struttura conditions (JSON)

Le condizioni sono un array di oggetti:

```typescript
type Condition = {
  field: "subject" | "body" | "email" | "tags" | ...
  operator: "contains" | "equals" | "starts_with" | "is_empty" | ...
  value: string
}

// Esempio: conditions
[
  { field: "body", operator: "contains", value: "urgente" },
  { field: "email", operator: "is_empty" }
]
```

L'applicazione delle condizioni usa logica AND (tutte devono essere soddisfatte).

## Server Actions

```typescript
createAutomationRule(workspaceId, data)
updateAutomationRule(automationId, data)
toggleAutomationRule(automationId, isEnabled: boolean)
deleteAutomationRule(automationId)
```

## Esecuzione automazioni (`lib/automations/`)

Le automazioni vengono valutate:
- Nelle API routes del widget dopo la ricezione di un messaggio
- Nelle server actions dopo la creazione di una conversazione

Il motore di automazione:
1. Carica tutte le regole `isEnabled: true` del workspace
2. Per ogni regola con trigger corrispondente, valuta le condizioni
3. Se le condizioni sono soddisfatte, esegue l'azione

## Componenti UI

In `components/automations/`:
- Form per creazione/modifica regola
- Selettori per trigger, condizioni, azione
- Toggle abilitazione/disabilitazione

## Permessi

- Solo `OWNER` e `ADMIN` possono creare/modificare automazioni
- Le automazioni si eseguono nel contesto del workspace, non dell'agente
