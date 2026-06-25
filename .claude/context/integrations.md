# Integrazioni Esterne

Vedi anche: [real-time.md](./real-time.md), [auth.md](./auth.md).

## Slack

### Configurazione
- **File:** `lib/slack.ts`, `actions/manage-slack-integration.ts`
- **OAuth:** `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`
- **Modello DB:** `SlackIntegration` (uno per workspace)

### Setup OAuth
1. Admin del workspace avvia OAuth via `/api/auth/slack`
2. Callback salva `accessToken` e `channelId` in `SlackIntegration`
3. Da quel momento, eventi configurati vengono notificati su Slack

### Notifiche configurabili (notificationSettings JSON)
```typescript
{
  newConversation: boolean    // nuova conversazione dal widget
  conversationClosed: boolean // conversazione chiusa
  conversationAssigned: boolean // assegnazione agente
}
```

### Server Action
```typescript
manageSlackIntegration(workspaceId, action: "connect" | "disconnect" | "update", data?)
```

---

## Email (Resend + Nodemailer)

### Provider
- **Transactional:** Resend (`resend` package)
- **Compatibility layer:** Nodemailer
- **API Key:** `RESEND_API_KEY`
- **File:** `lib/email.ts` (init Resend), `lib/email-notifications.ts`

### Email inviate dall'app

| Trigger | Template | Destinatario |
|---|---|---|
| Invito workspace | HTML inline | Email invitata |
| Reset password | HTML con link token | Utente |
| Magic link (auth) | Gestito da NextAuth/Resend | Utente |
| Nuovo messaggio visitatore | HTML notification | Agente assegnato |

### Notification email agli agenti
```typescript
// lib/email-notifications.ts
sendAgentNotificationEmail(conversationId: string, visitorMessage: string)
// From: GudDesk <noreply@guddesk.com>
// Reply-To: reply+{conversationId}@mail.guddesk.com
```

Il Reply-To speciale consente future implementazioni di risposta via email (inbound email handling).

### Inbound Email
```
POST /api/email/inbound
```
Webhook per gestire risposte email degli agenti (quando rispondono all'email di notifica). Parsea il `conversationId` dal Reply-To header.

---

## Google OAuth

- **Provider:** NextAuth Google provider
- **Env:** `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- **Scope:** profile + email
- **Comportamento:** crea o collega un `Account` al `User` esistente

Vedi [auth.md](./auth.md) per dettagli.

---

## Analytics

### Vercel Analytics
- Package: `@vercel/analytics`
- Integrato nel root layout
- No configurazione aggiuntiva se deployato su Vercel

### Microsoft Clarity (opzionale)
- Env: `NEXT_PUBLIC_CLARITY_PROJECT_ID`
- Script caricato nel layout se la variabile è presente
- Session recording e heatmaps

### Analytics custom
```prisma
model AnalyticsSnapshot {
  date                DateTime @unique
  newConversations    Int
  closedConversations Int
  avgResponseTime     Float?
  workspaceId         String
}
```
- Popolato da cron job: `POST /api/cron/analytics`
- Visualizzato in `components/analytics/` tramite Recharts

---

## ContentLayer (Content Management)

- **Pacchetto:** `contentlayer2`
- **Config:** `contentlayer.config.ts`
- **Contenuti:** `content/docs/`, `content/blog/`, `content/pages/`
- **Output:** `.contentlayer/generated/` (generato al build)

Document types:
- `Doc` — documentazione prodotto (`/docs/**`)
- `Post` — blog articles (`/blog/**`)
- `Page` — landing pages marketing (`/pages/**`)

MDX plugins: `remarkGfm`, `rehypeSlug`, `rehypePrettyCode` (github-dark), `rehypeAutolinkHeadings`

---

## Canned Responses

Non è un'integrazione esterna ma una feature interna:

```prisma
model CannedResponse {
  id          String @id
  name        String        // nome del template
  body        String        // testo del messaggio
  workspaceId String
}
```

Gestite via `CannedResponsePicker` nel `ReplyBox`. Actions: `createCannedResponse`, `updateCannedResponse`, `deleteCannedResponse`.
