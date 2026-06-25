# Funzionalità AI

Vedi anche: [inbox.md](./inbox.md), [database.md](./database.md).

## Stack AI

- **Provider:** Anthropic
- **SDK:** `@anthropic-ai/sdk` v0.76.0
- **Modello:** `claude-sonnet-4-5-20250929`
- **File client:** `lib/ai/client.ts`
- **Prompts:** `lib/ai/prompts.ts`
- **Actions AI:** `actions/ai/`
- **Usage tracking:** modello `AiUsageLog` nel DB

## Client wrapper (`lib/ai/client.ts`)

```typescript
// Ottieni istanza Anthropic (restituisce null se ANTHROPIC_API_KEY non configurata)
function getAnthropicClient(): Anthropic | null

// Chiamata unificata a Claude con logging automatico
async function callClaude(opts: {
  workspaceId: string
  feature: string           // identificatore per AiUsageLog
  system: string            // system prompt
  messages: Array<{
    role: "user" | "assistant"
    content: string
  }>
  maxTokens?: number        // default 1024
  conversationId?: string   // opzionale per log
}): Promise<string | null>
```

`callClaude` gestisce automaticamente:
- Istanziazione del client
- Chiamata API Anthropic
- Salvataggio del log di utilizzo in `AiUsageLog`
- Gestione errori (ritorna `null` in caso di fallimento)

## Prompts (`lib/ai/prompts.ts`)

Costanti con i system prompt per ogni feature:

| Costante | Feature |
|---|---|
| `REPLY_SUGGESTION_SYSTEM` | Suggerisce risposta dell'agente |
| `SUMMARIZE_SYSTEM` | Riassume la conversazione |
| `CATEGORIZE_SYSTEM` | Suggerisce categorie/tag |
| `SUGGEST_ARTICLES_SYSTEM` | Trova articoli KB rilevanti |
| `SENTIMENT_SYSTEM` | Analizza il tono del visitatore |

## Server Actions AI (`actions/ai/`)

```typescript
// Suggerisce una risposta per l'agente basata sul thread
generateReplySuggestion(conversationId): Promise<string | null>
// Input a Claude: storico messaggi formattato
// Output: risposta suggerita in testo libero

// Genera riassunto e lo salva in Conversation.aiSummary
summarizeConversation(conversationId): Promise<string | null>

// Categorizza e suggerisce tag
categorizeConversation(conversationId): Promise<string[] | null>

// Trova articoli KB rilevanti per la conversazione
suggestArticles(conversationId): Promise<Article[] | null>

// Analizza sentiment del visitatore
analyzeSentiment(conversationId): Promise<{
  sentiment: "positive" | "neutral" | "negative"
  score: number
} | null>
```

## AI Usage Tracking

Ogni chiamata AI viene loggata in `AiUsageLog`:

```prisma
model AiUsageLog {
  id             String   @id
  feature        String   // nome feature (es. "reply_suggestion")
  inputTokens    Int
  outputTokens   Int
  model          String   // "claude-sonnet-4-5-20250929"
  conversationId String?
  workspaceId    String
  createdAt      DateTime
}
```

Usato per:
- Monitoraggio costi per workspace
- Dashboard analytics AI usage

## Comportamento senza API Key

Se `ANTHROPIC_API_KEY` non è configurata:
- `getAnthropicClient()` ritorna `null`
- `callClaude()` ritorna `null` silenziosamente
- Le feature AI nel UI mostrano stato "non disponibile"

## Estendere le feature AI

Per aggiungere una nuova feature AI:

1. Aggiungi il system prompt in `lib/ai/prompts.ts`
2. Crea la server action in `actions/ai/`
3. Chiama `callClaude()` con il feature name appropriato
4. Aggiungi il bottone/trigger nel componente UI relevante (tipicamente in `components/inbox/conversation-detail-sidebar.tsx`)
5. Il logging è automatico tramite `callClaude()`

## Nota sull'integrazione con il modello

Per aggiornare il modello Claude, modificare la costante del model ID in `lib/ai/client.ts`. Verificare la compatibilità dei prompt con il modello scelto. I modelli disponibili nel 2025-2026 sono: `claude-sonnet-4-6`, `claude-opus-4-8`, `claude-haiku-4-5-20251001`.
