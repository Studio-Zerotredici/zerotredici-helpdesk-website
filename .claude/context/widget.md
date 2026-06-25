# Widget Embeddabile

Vedi anche: [real-time.md](./real-time.md), [knowledge-base.md](./knowledge-base.md), [api-routes.md](./api-routes.md).

## Panoramica

Il widget è un componente JavaScript embeddabile che i clienti integrano nei propri siti. Permette ai visitatori di avviare conversazioni di supporto senza registrazione.

## Architettura

- **Framework:** Preact (lightweight, ~3KB vs React ~40KB)
- **State:** Preact Signals
- **Build:** Vite con output UMD + ESM
- **Percorso sorgente:** `packages/widget/src/`
- **Output build:** `public/widget.js` (UMD, usato in produzione)
- **Build command:** `pnpm build:widget`

## Integrazione sul sito del cliente

```html
<script>
  window.GudDeskSettings = {
    appId: "workspace-app-id",   // da WidgetSettings del workspace
    // Opzionale: identificazione visitor
    visitor: {
      externalId: "user-123",
      name: "Mario Rossi",
      email: "mario@example.com",
      // metadata custom
    }
  };
</script>
<script async src="https://app.guddesk.com/widget.js"></script>
```

## Funzionalità widget

- Chat real-time con agenti (via Pusher)
- Storico conversazioni del visitatore
- Search nella knowledge base
- Identificazione visitatore (opzionale)
- Supporto dark/light mode
- Posizione configurabile (bottom-right / bottom-left)
- Colore primario personalizzabile

## API Routes del widget

Tutti i prefissi `/api/widget/`:

| Endpoint | Metodo | Descrizione |
|---|---|---|
| `/config` | GET | Carica `WidgetSettings` dal `appId` |
| `/auth` | POST | Genera token JWT visitatore |
| `/visitors` | GET/POST | Identifica o crea visitatore |
| `/conversations` | GET/POST | Lista o crea conversazione |
| `/conversations/[id]/messages` | GET | Carica messaggi |
| `/conversations/[id]/messages` | POST | Invia messaggio visitatore |
| `/articles/search` | GET | Cerca articoli KB (`?q=testo`) |

## Autenticazione visitatori

Il widget usa un token JWT separato dal sistema di autenticazione NextAuth:

1. Widget chiama `POST /api/widget/auth` con `appId` e `visitorId` opzionale
2. Server genera JWT firmato con `VISITOR_TOKEN_SECRET`
3. Token incluso in ogni richiesta widget come `Authorization: Bearer xxx`
4. `lib/visitor-auth.ts` gestisce verifica e parsing del token

## Visitor identification

```typescript
// Passato da GudDeskSettings.visitor
{
  externalId: string    // ID nel sistema del cliente
  name?: string
  email?: string
  metadata?: Record<string, any>  // salvato nel campo Visitor.metadata (JSON)
}
```

Il campo `externalId` viene usato per ritrovare un visitatore già esistente e collegare le conversazioni precedenti.

## Real-time nel widget

Il widget si iscrive a canali Pusher:
- `presence-visitor-{visitorId}` — per ricevere messaggi degli agenti
- Autenticazione via `POST /api/pusher/auth`

Vedi [real-time.md](./real-time.md).

## WidgetSettings (configurazione workspace)

Configurabile da `workspace/[slug]/settings`:

```prisma
model WidgetSettings {
  primaryColor       String?
  position           String?   // "bottom-right" | "bottom-left"
  welcomeMessage     String?
  requireEmail       Boolean   @default(false)
  pageVisibilityMode String?   // "all" | "whitelist" | "blacklist"
  visibilityPages    String[]  // URL patterns per visibilità
}
```

Il campo `pageVisibilityMode` + `visibilityPages` controlla su quali pagine del sito cliente appare il widget.

## Build e distribuzione

```bash
# Build standalone del widget
pnpm build:widget

# Output: public/widget.js (UMD bundle)
# Anche: packages/widget/dist/ (ESM per npm)
```

La build del widget è inclusa automaticamente nel `pnpm build` completo (via `build:widget` script).

## Widget Preview

`components/widget-preview/` contiene un componente che simula il widget nel dashboard, usato nella pagina settings per preview live delle modifiche alla configurazione.
