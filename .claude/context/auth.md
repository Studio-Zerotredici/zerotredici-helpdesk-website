# Autenticazione e Autorizzazione

Vedi anche: [database.md](./database.md) per i modelli `User`, `Account`, `Session`.

## Stack

- **NextAuth.js** v5 beta (`next-auth@5.0.0-beta.30`)
- **Adapter:** `@auth/prisma-adapter` → Prisma
- **Password hashing:** `bcryptjs`
- **JWT:** `jsonwebtoken` (usato per token reset password e inviti workspace)

## File principali

| File | Ruolo |
|---|---|
| `auth.ts` | Config NextAuth: callbacks JWT/session, Prisma adapter |
| `auth.config.ts` | Definizione providers (Google, Resend, Credentials) |
| `middleware.ts` | Protezione route (redirect a `/login`) |
| `lib/session.ts` | `getCurrentUser()`, `getSession()` |
| `lib/workspace.ts` | Guards RBAC: `requireWorkspaceMember()`, `requireWorkspaceRole()` |
| `actions/auth/` | Register, forgotPassword, resetPassword |

## Providers

### 1. Credentials (email + password)
- Schema validazione: `userLoginSchema` (`lib/validations/auth.ts`)
- Lookup utente su `User` table
- Confronto hash con `bcryptjs.compare()`
- Non richiede verifica email

### 2. Google OAuth
- Env: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- Account collegato alla tabella `Account`

### 3. Resend (Magic Link)
- Env: `RESEND_API_KEY`
- From: `GudDesk App <onboarding@resend.dev>`
- Token salvato in `VerificationToken`

## Sessione (JWT strategy)

Il JWT estende la sessione con campi workspace:

```typescript
// session.user contiene:
{
  id: string                   // token.sub
  role: UserRole               // "ADMIN" | "USER"
  activeWorkspaceId: string
  activeWorkspaceRole: WorkspaceRole  // "OWNER" | "ADMIN" | "AGENT" | "VIEWER"
  activeWorkspaceSlug: string
}
```

Il workspace attivo viene risolto nel callback `jwt` al primo accesso o su `trigger: "update"`.

## RBAC (Role-Based Access Control)

Due livelli di ruolo:

**`UserRole`** (globale):
- `ADMIN` — accesso admin sistema
- `USER` — utente normale

**`WorkspaceRole`** (per workspace):
- `OWNER` — pieno controllo
- `ADMIN` — gestione team e settings
- `AGENT` — gestisce conversazioni
- `VIEWER` — sola lettura

### Guard functions (`lib/workspace.ts`)

```typescript
// Verifica che l'utente sia membro del workspace
await requireWorkspaceMember(workspaceId, userId)

// Verifica ruolo specifico (lancia errore se insufficiente)
await requireWorkspaceRole(workspaceId, userId, ["OWNER", "ADMIN"])
```

Queste devono essere chiamate all'inizio di ogni server action che opera su un workspace.

## Flusso reset password

1. `forgotPassword()` action → genera token con `jsonwebtoken`, salva in `PasswordResetToken`
2. Invia email con link `/reset-password?token=xxx`
3. `resetPassword()` action → verifica token, aggiorna hash password

## Flusso invito workspace

1. `inviteWorkspaceMember()` → crea `WorkspaceInvitation` con token e scadenza
2. Email inviata con link `/workspace/[slug]/invitation?token=xxx`
3. `acceptInvitation()` → verifica token, crea `WorkspaceMember`

## Middleware

`middleware.ts` usa la sessione NextAuth per:
- Redirigere non autenticati → `/login`
- Proteggere tutte le route `/dashboard/**` e `/workspace/**`
- Route pubbliche: `/`, `/login`, `/register`, `/api/widget/**`, `/api/email/**`

## Modelli DB correlati

```prisma
model User {
  id       String   @id
  email    String   @unique
  password String?  // null per OAuth
  role     UserRole @default(USER)
  ...
}

model PasswordResetToken {
  id      String   @id
  email   String
  token   String   @unique
  expires DateTime
}

model WorkspaceInvitation {
  id        String           @id
  email     String
  token     String           @unique
  expiresAt DateTime
  status    InvitationStatus
  workspaceId String
}
```
