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

### Sender: `EMAIL_FROM` / `EMAIL_REPLY_TO_DOMAIN`

`auth.config.ts` (magic link), `actions/forgot-password.ts`,
`actions/invite-workspace-member.ts` e `lib/email-notifications.ts` leggono
il sender da `env.EMAIL_FROM` (es. `GudDesk <support@yourdomain.com>`),
con un fallback dev-only se non impostata. **Il dominio in `EMAIL_FROM` deve
essere verificato nell'account Resend** prima del go-live — vedi
[`DOKPLOY.md`](../../DOKPLOY.md) step 5.

I vecchi default hardcoded sono stati rimossi perché non production-safe:
`onboarding@resend.dev` (sandbox Resend, consegna solo all'email
dell'account Resend proprietario) e sender su `guddesk.com` (dominio non di
nostra proprietà).

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
// From: env.EMAIL_FROM
// Reply-To: reply+{conversationId}@{env.EMAIL_REPLY_TO_DOMAIN}
```

Il Reply-To speciale consente la risposta via email (inbound email
handling, vedi sotto). `EMAIL_REPLY_TO_DOMAIN` è opzionale — necessario solo
se si vuole abilitare questa feature, e richiede l'inbound routing di
Resend configurato sul dominio.

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
