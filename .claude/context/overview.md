# GudDesk — Panoramica del Progetto

## Identità

- **Nome app:** GudDesk
- **Repository:** zerotredici-helpdesk-website
- **Tipo:** Web app full-stack per helpdesk e customer support
- **Framework:** Next.js 16.1.6 con App Router, React 19, TypeScript 5.7.3
- **Package manager:** pnpm 10.32.1

## Stack tecnologico

| Layer | Tecnologia |
|---|---|
| Frontend | Next.js App Router, React 19, Tailwind CSS 4, Radix UI |
| Backend | Next.js Server Actions + API Routes |
| Database | PostgreSQL via Prisma 6.19.3 (adapter: `@prisma/adapter-pg`) |
| Auth | NextAuth.js 5 (beta.30) |
| Real-time | Pusher |
| Email | Resend + Nodemailer |
| AI | Anthropic SDK (`claude-sonnet-4-5-20250929`) |
| Validazione | Zod + t3-oss/env-nextjs |
| Deployment | Docker (multi-stage) + docker-compose |

## Struttura cartelle di alto livello

```
app/
├── (auth)/           → Login, register, forgot/reset password
├── (protected)/      → Dashboard, workspace (inbox, articles, automations, settings)
├── (marketing)/      → Home, blog, integrations, landing pages
├── (docs)/           → Documentazione prodotto (ContentLayer MDX)
├── (help-center)/    → Help center pubblico per visitatori
└── api/              → API REST interne + widget + webhook

actions/              → Server Actions Next.js (logica business)
components/           → React components suddivisi per dominio
lib/                  → Utilities, client db, AI, pusher, email, validazioni
prisma/               → Schema + migrazioni
packages/widget/      → Widget embeddabile (Preact, build Vite)
content/              → Contenuti MDX (docs, blog, pages marketing)
emails/               → Template email HTML (React Email)
config/               → Configurazioni app
hooks/                → React hooks custom
types/                → Definizioni TypeScript
```

## Sezioni principali dell'app

Ogni sezione ha un file dedicato nella cartella `.claude/context/`:

| Sezione | File | Descrizione |
|---|---|---|
| Autenticazione | [auth.md](./auth.md) | NextAuth, providers, sessioni, RBAC |
| Database | [database.md](./database.md) | Schema Prisma, modelli, relazioni |
| Inbox / Conversazioni | [inbox.md](./inbox.md) | Gestione conversazioni e messaggi |
| Knowledge Base | [knowledge-base.md](./knowledge-base.md) | Articoli e collections |
| Automazioni | [automations.md](./automations.md) | Regole di automazione |
| Widget embeddabile | [widget.md](./widget.md) | Widget Preact per siti esterni |
| Funzionalità AI | [ai.md](./ai.md) | Claude, prompts, AI actions |
| Real-time | [real-time.md](./real-time.md) | Pusher channels ed eventi |
| Integrazioni esterne | [integrations.md](./integrations.md) | Slack, email, analytics |
| Deployment | [deployment.md](./deployment.md) | Docker, env vars, CI/CD |
| API Routes | [api-routes.md](./api-routes.md) | Tutte le API REST |
| Server Actions | [server-actions.md](./server-actions.md) | Tutte le server actions |

## Flusso dati principale

```
Visitor widget → POST /api/widget/conversations/[id]/messages
  → DB: save message (type: VISITOR)
  → Pusher: notify workspace agents
  → Email: notify assigned agent

Agent reply → sendMessage() action
  → DB: save message (type: AGENT / NOTE)
  → Pusher: update widget visitor
  → AI features opzionali (suggestion, summary, sentiment)
```

## Convenzioni chiave

- Server actions ritornano `{ status: "success" | "error", message?: string }`
- RBAC enforced tramite `requireWorkspaceMember()` / `requireWorkspaceRole()`
- Ogni workspace ha un `appId` univoco usato dal widget
- `activeWorkspaceId` / `activeWorkspaceSlug` sono nel JWT della sessione
- Il widget è compilato come UMD in `public/widget.js`

## Variabili d'ambiente richieste

```bash
NEXT_PUBLIC_APP_URL
AUTH_SECRET
GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
DATABASE_URL
RESEND_API_KEY
PUSHER_APP_ID / PUSHER_SECRET / NEXT_PUBLIC_PUSHER_KEY / NEXT_PUBLIC_PUSHER_CLUSTER
ANTHROPIC_API_KEY
SLACK_CLIENT_ID / SLACK_CLIENT_SECRET        # opzionali
NEXT_PUBLIC_CLARITY_PROJECT_ID               # opzionale
```

Dettaglio completo in [deployment.md](./deployment.md).
