# Database — Schema e Modelli

Vedi anche: [auth.md](./auth.md), [inbox.md](./inbox.md), [knowledge-base.md](./knowledge-base.md).

## Tecnologia

- **ORM:** Prisma 6.19.3
- **Driver:** `@prisma/adapter-pg` (PostgreSQL nativo)
- **Database:** PostgreSQL (Neon supportato)
- **Schema:** `prisma/schema.prisma` (≈ 463 righe)
- **Client singleton:** `lib/db.ts`

### Singleton Prisma

```typescript
// lib/db.ts
import { PrismaClient } from "@prisma/client"
import { PrismaPg } from "@prisma/adapter-pg"

// Singleton con cache per dev (evita hot-reload issues)
export let prisma: PrismaClient
```

## Enumerazioni

```prisma
enum UserRole           { ADMIN, USER }
enum WorkspaceRole      { OWNER, ADMIN, AGENT, VIEWER }
enum InvitationStatus   { PENDING, ACCEPTED, EXPIRED }
enum ConversationStatus { OPEN, SNOOZED, CLOSED }
enum MessageType        { VISITOR, AGENT, NOTE, SYSTEM, BOT }

enum AutomationTrigger  {
  CONVERSATION_CREATED, MESSAGE_RECEIVED, TAG_ADDED,
  CONVERSATION_ASSIGNED, STATUS_CHANGED, ...
}
enum AutomationAction   {
  ASSIGN_TO, ADD_TAG, SEND_MESSAGE, NOTIFY_SLACK, ...
}
```

## Modelli

### Autenticazione (NextAuth)

```prisma
model User {
  id            String    @id @default(cuid())
  name          String?
  email         String    @unique
  emailVerified DateTime?
  password      String?   // null per OAuth users
  image         String?
  role          UserRole  @default(USER)
  accounts      Account[]
  sessions      Session[]
  workspaceMembers WorkspaceMember[]
}

model Account { ... }   // OAuth provider data
model Session { ... }   // NextAuth sessions
model VerificationToken { ... }
model PasswordResetToken {
  id      String   @id
  email   String
  token   String   @unique
  expires DateTime
}
```

### Workspace

```prisma
model Workspace {
  id      String  @id @default(cuid())
  name    String
  slug    String  @unique
  logo    String?
  appId   String  @unique   // usato dal widget per identificare il workspace
  members WorkspaceMember[]
  invitations WorkspaceInvitation[]
  conversations Conversation[]
  widgetSettings WidgetSettings?
  helpCenterSettings HelpCenterSettings?
  ...
}

model WorkspaceMember {
  id          String        @id
  userId      String
  workspaceId String
  role        WorkspaceRole @default(AGENT)
  user        User          @relation(...)
  workspace   Workspace     @relation(...)
  @@unique([userId, workspaceId])
}

model WorkspaceInvitation {
  id          String           @id
  email       String
  token       String           @unique
  expiresAt   DateTime
  status      InvitationStatus @default(PENDING)
  workspaceId String
  invitedById String
}
```

### Conversazioni (Inbox)

```prisma
model Visitor {
  id         String  @id
  externalId String?          // ID utente dal sito che integra il widget
  name       String?
  email      String?
  avatarUrl  String?
  metadata   Json?            // dati custom passati dall'integratore
  workspaceId String
  conversations Conversation[]
}

model Conversation {
  id          String             @id
  status      ConversationStatus @default(OPEN)
  subject     String?
  priority    Int?
  tags        String[]
  assigneeId  String?            // WorkspaceMember assegnato
  snoozedUntil DateTime?
  aiSummary   String?            // generato dall'AI
  visitorId   String
  workspaceId String
  messages    Message[]
  createdAt   DateTime
  updatedAt   DateTime
}

model Message {
  id             String      @id
  type           MessageType  // VISITOR | AGENT | NOTE | SYSTEM | BOT
  body           String
  attachments    Json?
  senderId       String?      // WorkspaceMember (null per VISITOR/SYSTEM)
  conversationId String
  createdAt      DateTime
}
```

### Knowledge Base

```prisma
model Collection {
  id          String   @id
  name        String
  slug        String
  description String?
  isPublished Boolean  @default(false)
  workspaceId String
  articles    Article[]
}

model Article {
  id          String   @id
  title       String
  slug        String
  body        String   // contenuto HTML/Markdown
  excerpt     String?
  isPublished Boolean  @default(false)
  viewCount   Int      @default(0)
  helpfulCount Int     @default(0)
  authorId    String   // WorkspaceMember
  collectionId String
  workspaceId String
}

model HelpCenterSettings {
  id           String  @id
  title        String?
  subtitle     String?
  primaryColor String?
  logoUrl      String?
  workspaceId  String  @unique
}
```

### Widget

```prisma
model WidgetSettings {
  id                  String  @id
  primaryColor        String?
  position            String? // "bottom-right" | "bottom-left"
  welcomeMessage      String?
  requireEmail        Boolean @default(false)
  pageVisibilityMode  String? // "all" | "whitelist" | "blacklist"
  visibilityPages     String[]
  workspaceId         String  @unique
}
```

### Automazioni

```prisma
model AutomationRule {
  id           String            @id
  name         String
  trigger      AutomationTrigger
  conditions   Json              // array di condizioni
  action       AutomationAction
  actionConfig Json              // parametri dell'azione
  isEnabled    Boolean           @default(true)
  workspaceId  String
}
```

### Integrazioni

```prisma
model SlackIntegration {
  id                   String  @id
  accessToken          String
  channelId            String
  notificationSettings Json    // quali eventi notificare
  workspaceId          String  @unique
}

model CannedResponse {
  id          String @id
  name        String
  body        String
  workspaceId String
}
```

### Analytics

```prisma
model AiUsageLog {
  id             String   @id
  feature        String   // "reply_suggestion" | "summarize" | ...
  inputTokens    Int
  outputTokens   Int
  model          String
  conversationId String?
  workspaceId    String
  createdAt      DateTime
}

model AnalyticsSnapshot {
  id                  String   @id
  date                DateTime @unique
  newConversations    Int
  closedConversations Int
  avgResponseTime     Float?
  workspaceId         String
}
```

## Convenzioni

- ID: `@id @default(cuid())` su tutti i modelli
- Timestamp: `createdAt` e `updatedAt` con `@default(now())` e `@updatedAt`
- Relazioni: sempre bidirezionali con `@relation`
- JSON fields: usati per `conditions`, `actionConfig`, `metadata`, `attachments`
- `String[]` arrays: usati per `tags`, `visibilityPages`

## Migrazioni

Le migrazioni sono in `prisma/migrations/`. Per creare una nuova:

```bash
pnpm prisma migrate dev --name nome-migrazione
```

Per generare il client dopo modifiche allo schema:

```bash
pnpm prisma generate
```
