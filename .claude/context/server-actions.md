# Server Actions

Vedi anche: [auth.md](./auth.md), [inbox.md](./inbox.md), [knowledge-base.md](./knowledge-base.md).

## Panoramica

Le server actions Next.js sono il layer di business logic principale. Sono file nella cartella `actions/` e vengono chiamate direttamente dai componenti React.

## Convenzione di ritorno

```typescript
type ActionResult = {
  status: "success" | "error"
  message?: string
  data?: any
}
```

Ogni action inizia verificando l'autenticazione e i permessi RBAC prima di operare sul DB.

---

## Autenticazione (`actions/auth/`)

### `register(data: RegisterInput)`
- Valida con `userRegisterSchema`
- Hash password con `bcryptjs`
- Crea `User` in DB
- Non fa login automatico

### `forgotPassword(email: string)`
- Genera token JWT con scadenza
- Salva `PasswordResetToken`
- Invia email con link reset

### `resetPassword(token: string, newPassword: string)`
- Verifica token non scaduto
- Aggiorna hash password utente
- Elimina `PasswordResetToken` usato

---

## Messaggi (`actions/send-message.ts`)

### `sendMessage(conversationId, body, type, attachments?)`
- `type`: `"AGENT"` o `"NOTE"`
- Verifica `requireWorkspaceMember()`
- Salva `Message` in DB
- Emette evento Pusher `message:created`
- Se primo messaggio agente → `sendAgentNotificationEmail()`

---

## Conversazioni

### `assignConversation(conversationId, assigneeId)`
- Aggiorna `Conversation.assigneeId`
- Emette Pusher `conversation:assigned`

### `updateConversationStatus(conversationId, status)`
- `status`: `"OPEN"` | `"SNOOZED"` | `"CLOSED"`
- Per `SNOOZED`: richiede `snoozedUntil` datetime

### `tagConversation(conversationId, tags: string[])`
- Sostituisce i tag della conversazione

### `bulkConversationActions(conversationIds, action, params)`
- Operazioni in batch su più conversazioni
- Actions: close, assign, tag, delete

---

## Articoli (`actions/manage-article.ts`)

### `createArticle(workspaceId, collectionId, data)`
- Richiede ruolo `AGENT` o superiore

### `updateArticle(articleId, data)`
- Aggiorna titolo, body, excerpt

### `publishArticle(articleId, publish: boolean)`
- Toggle `isPublished`
- Richiede ruolo `ADMIN` o superiore

### `deleteArticle(articleId)`

### `articleFeedback(articleId, helpful: boolean)`
- Incrementa `helpfulCount` o `notHelpfulCount`
- Chiamabile da visitatori (no auth richiesta)

---

## Collections (`actions/manage-collection.ts`)

### `createCollection(workspaceId, data)`
### `updateCollection(collectionId, data)`
### `deleteCollection(collectionId)`
- Elimina anche tutti gli articoli della collection

---

## Automazioni (`actions/manage-automation.ts`)

### `createAutomationRule(workspaceId, data)`
- `data`: nome, trigger, conditions (JSON), action, actionConfig (JSON)

### `updateAutomationRule(automationId, data)`

### `toggleAutomationRule(automationId, isEnabled: boolean)`

### `deleteAutomationRule(automationId)`

---

## Workspace (`actions/workspace/`)

### `createWorkspace(name: string)`
- Genera slug univoco da nome
- Genera `appId` univoco (UUID)
- Crea `WorkspaceMember` con ruolo `OWNER`
- Crea `WidgetSettings` default
- Crea `HelpCenterSettings` default
- Aggiorna sessione con nuovo workspace attivo

### `inviteWorkspaceMember(workspaceId, email, role)`
- Richiede ruolo `OWNER` o `ADMIN`
- Crea `WorkspaceInvitation` con token JWT
- Invia email di invito

### `acceptInvitation(token: string)`
- Verifica token non scaduto e status `PENDING`
- Crea `WorkspaceMember`
- Aggiorna `InvitationStatus.ACCEPTED`
- Fa switch al workspace

### `updateWorkspaceMemberRole(memberId, role)`
- Richiede ruolo `OWNER` o `ADMIN`

### `removeWorkspaceMember(memberId)`
- Richiede ruolo `OWNER` o `ADMIN`

### `switchWorkspace(workspaceId)`
- Aggiorna `activeWorkspaceId` nella sessione (trigger `update`)

---

## Settings (`actions/settings/`)

### `updateWidgetSettings(workspaceId, data)`
- Aggiorna `WidgetSettings`
- Richiede ruolo `OWNER` o `ADMIN`

### `updateHelpCenterSettings(workspaceId, data)`
- Aggiorna `HelpCenterSettings`

### `updateWorkspaceSettings(workspaceId, data)`
- Aggiorna nome, logo workspace

### `updateUserName(name: string)`
- Aggiorna `User.name` dell'utente corrente

### `deleteAccount()`
- Elimina `User` e tutti i dati associati

---

## AI (`actions/ai/`)

Vedi [ai.md](./ai.md) per dettagli.

- `generateReplySuggestion(conversationId)`
- `summarizeConversation(conversationId)`
- `categorizeConversation(conversationId)`
- `suggestArticles(conversationId)`
- `analyzeSentiment(conversationId)`

---

## Integrazioni

### `manageSlackIntegration(workspaceId, action, data?)`
- `action`: `"connect"` | `"disconnect"` | `"update"`

---

## Canned Responses

### `createCannedResponse(workspaceId, name, body)`
### `updateCannedResponse(id, name, body)`
### `deleteCannedResponse(id)`

---

## Pattern comune nelle actions

```typescript
"use server"

import { getCurrentUser } from "@/lib/session"
import { requireWorkspaceRole } from "@/lib/workspace"
import { revalidatePath } from "next/cache"

export async function exampleAction(workspaceId: string, data: InputType) {
  // 1. Auth check
  const user = await getCurrentUser()
  if (!user) return { status: "error", message: "Unauthorized" }

  // 2. RBAC check
  await requireWorkspaceRole(workspaceId, user.id, ["OWNER", "ADMIN"])

  // 3. Validazione input (Zod)
  const parsed = schema.safeParse(data)
  if (!parsed.success) return { status: "error", message: "Invalid input" }

  // 4. DB operation
  await prisma.something.create({ ... })

  // 5. Revalidate cache
  revalidatePath(`/workspace/${workspaceSlug}/...`)

  return { status: "success" }
}
```
