# Deployment e Configurazione

Vedi anche: [overview.md](./overview.md).

## Docker

### Dockerfile (multi-stage)

**Stage 1 — base** (`node:20.18-alpine`):
- Installa `pnpm@10.32.1` via corepack

**Stage 2 — deps**:
- Copia `package.json`, `pnpm-lock.yaml`, `prisma/schema.prisma`
- Esegue `pnpm install --frozen-lockfile`

**Stage 3 — builder**:
- Copia node_modules + codice sorgente
- Imposta env placeholder per la validazione build-time (t3-oss)
- Build widget: `pnpm build:widget`
- Genera Prisma client: `pnpm prisma generate`
- Build ContentLayer: `pnpm build:content`
- Build Next.js: `pnpm next build`

**Stage 4 — runner** (`node:20.18-alpine`):
- Copia solo `.next/standalone`, `.next/static`, `public/`, `prisma/`
- Installa la Prisma CLI in una directory isolata `/opt/prisma-cli` (vedi
  sotto — non copiata dallo stage builder)
- Copia `entrypoint.sh` come `ENTRYPOINT`
- User: `nextjs` (UID 1001, non-root)
- Porta: `3000`

### Prisma CLI nel runner stage: perché un'installazione isolata

Lo stage runner NON copia `node_modules/prisma` dal builder con una `COPY`
semplice. Con pnpm, `node_modules/prisma` è un symlink dentro
`node_modules/.pnpm`, e le dipendenze private della CLI
(`@prisma/engines`, `@prisma/config`, ...) vivono come symlink *fratelli*
nello stesso store virtuale — non nel `node_modules/@prisma` top-level
(quello contiene solo `@prisma/client` e `@prisma/adapter-pg`, dipendenze
dirette dell'app). Una `COPY` che prende solo `node_modules/prisma` +
`node_modules/@prisma` lascia questi symlink "orfani" nello stage runner,
causando `Cannot find module '@prisma/engines'` all'avvio.

La soluzione (Dockerfile, stage runner): un `RUN` isolato crea
`/opt/prisma-cli`, legge la versione esatta di `prisma` da
`package.json` (`devDependencies.prisma`), e fa un `pnpm add` scoped in
quella directory — così pnpm risolve correttamente l'intero albero di
dipendenze della CLI in un solo layer, senza toccare il `node_modules` di
`/app` (che contiene già l'output tracciato dello standalone build di
Next.js, con versioni pinnate diverse da quelle di `package.json`).

`entrypoint.sh` invoca quindi
`node /opt/prisma-cli/node_modules/prisma/build/index.js migrate deploy --schema=/app/prisma/schema.prisma`
con path assoluti.

### entrypoint.sh — migrazioni al boot

```sh
#!/bin/sh
set -e
node /opt/prisma-cli/node_modules/prisma/build/index.js migrate deploy --schema=/app/prisma/schema.prisma
exec node server.js
```

Eseguito su **ogni** avvio del container (`ENTRYPOINT` del Dockerfile).
`migrate deploy` è idempotente — applica solo le migrazioni non ancora
eseguite, quindi è sicuro rieseguirlo ad ogni boot. Il primo deploy crea lo
schema da zero, senza bisogno di un `pnpm prisma db push` manuale.

### docker-compose.yml — stack unico (app + Postgres bundled)

`docker-compose.yml` include Postgres come servizio *sibling* nello stesso
stack (non nello stesso container/Dockerfile dell'app — sarebbe un
anti-pattern: niente restart/backup/scaling indipendenti del DB). `app`
aspetta che `postgres` sia `service_healthy` prima di avviarsi
(`depends_on` + `healthcheck` con `pg_isready`); `DATABASE_URL` viene
calcolato automaticamente via interpolazione compose da `POSTGRES_USER` /
`POSTGRES_PASSWORD` / `POSTGRES_DB` — non va impostato a mano in questo
percorso.

```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    env_file: .env
    environment:
      AUTH_TRUST_HOST: "true"
      DATABASE_URL: "postgresql://${POSTGRES_USER:-guddesk}:${POSTGRES_PASSWORD:?...}@postgres:5432/${POSTGRES_DB:-guddesk}?sslmode=disable"
    depends_on:
      postgres:
        condition: service_healthy
    networks: [gateway, internal]

  postgres:
    image: postgres:16-alpine
    environment: {POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB}
    volumes: ["postgres-data:/var/lib/postgresql/data"]
    networks: [internal]        # nessun ports: — mai esposto sull'host
    healthcheck: {test: "pg_isready -U ... -d ...", interval: 5s, retries: 10}

networks:
  gateway:
    external: true   # rete esterna per reverse proxy (Dokploy/Traefik)
  internal:           # rete interna dello stack, non esterna

volumes:
  postgres-data:
```

**Nota:** `AUTH_TRUST_HOST=true` è richiesto in produzione quando si usa un reverse proxy (Nginx, Traefik, Caddy).

Su Dokploy si usa il deploy type **Compose** (non Application/Dockerfile
diretto) per ottenere questo stack unico — Dokploy builda `app` dal
`Dockerfile` del repo via `build: .` e avvia `postgres` insieme, sulla rete
interna, mai esposto su una porta host. Un dominio+TLS va assegnato al
servizio `app` (porta 3000) dalla UI di Dokploy, stesso pattern usato per
Soketi. **Nota appresa da un deploy Dokploy Compose precedente (Termix):**
i valori impostati nel tab Environment di Dokploy raggiungono il container
solo se il compose file li referenzia esplicitamente nel blocco
`environment:` (come interpolazione `${VAR}`) — non dare per scontato un
passthrough implicito.

Se in futuro serve un Postgres esternalizzato (backup/scaling indipendenti
dall'app, es. Dokploy managed Postgres) si rimuove il servizio `postgres` e
le `POSTGRES_*` da `docker-compose.yml`, si imposta `DATABASE_URL`
direttamente, e si può tornare al deploy type Application/Dockerfile puro.

Vedi [`DOKPLOY.md`](../../DOKPLOY.md) nella root del repo per il percorso
di deploy completo specifico di Studio Zerotredici (in due fasi: quick
start con Pusher Cloud + stack bundled, poi personalizzazione con Soketi
self-hosted).

### Comandi Docker

```bash
# Build e avvio
docker-compose up --build -d

# Solo build
docker build -t guddesk .

# Logs
docker-compose logs -f app
```

---

## Variabili d'Ambiente

### Obbligatorie

```bash
# App
NEXT_PUBLIC_APP_URL=https://app.guddesk.com

# Auth
AUTH_SECRET=<random-32-chars>   # openssl rand -base64 32
AUTH_TRUST_HOST=true             # obbligatorio con reverse proxy

# Database — default: Postgres bundled in docker-compose.yml (vedi sopra),
# DATABASE_URL calcolato automaticamente da questi tre:
POSTGRES_USER=guddesk
POSTGRES_PASSWORD=<password-reale>
POSTGRES_DB=guddesk
# Alternativa: Postgres esterno/managed — DATABASE_URL diretto, rimuovendo
# il servizio postgres da docker-compose.yml
# DATABASE_URL=postgresql://user:password@host:5432/dbname?sslmode=require

# Email
RESEND_API_KEY=re_xxxxx
EMAIL_FROM="GudDesk <support@yourdomain.com>"      # dominio verificato su Resend
EMAIL_REPLY_TO_DOMAIN=mail.yourdomain.com          # opzionale, per reply-by-email

# Real-time — Opzione A: Pusher Cloud
PUSHER_APP_ID=
PUSHER_SECRET=
NEXT_PUBLIC_PUSHER_KEY=
NEXT_PUBLIC_PUSHER_CLUSTER=eu

# Real-time — Opzione B: Soketi self-hosted (alternativa a Pusher Cloud,
# vedi real-time.md). PUSHER_HOST presente ha priorità su
# NEXT_PUBLIC_PUSHER_CLUSTER.
PUSHER_HOST=ws.yourdomain.com
PUSHER_PORT=443
PUSHER_USE_TLS=true
NEXT_PUBLIC_PUSHER_HOST=ws.yourdomain.com
NEXT_PUBLIC_PUSHER_PORT=443
NEXT_PUBLIC_PUSHER_FORCE_TLS=true

# AI
ANTHROPIC_API_KEY=sk-ant-xxxxx
```

`EMAIL_FROM` / `EMAIL_REPLY_TO_DOMAIN` sostituiscono i vecchi sender
hardcoded (`onboarding@resend.dev` sandbox, `guddesk.com` non di nostra
proprietà) in `auth.config.ts`, `actions/forgot-password.ts`,
`actions/invite-workspace-member.ts` e `lib/email-notifications.ts` — vedi
[integrations.md](./integrations.md).

### Opzionali

```bash
# OAuth Google
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# Slack integration
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=

# Analytics
NEXT_PUBLIC_CLARITY_PROJECT_ID=
```

### Validazione env

Le variabili sono validate con `t3-oss/env-nextjs` in `env.mjs`. Il build fallisce se le variabili obbligatorie mancano, a meno che non si imposti `SKIP_ENV_VALIDATION=true`.

Durante il Docker build, vengono usati placeholder per superare la validazione:
```dockerfile
ENV NEXT_PUBLIC_APP_URL=http://localhost:3000
ENV AUTH_SECRET=placeholder
# ...etc
```

---

## Next.js Config (`next.config.js`)

```javascript
output: "standalone"    // build minimale per Docker
reactStrictMode: true
serverExternalPackages: ["@prisma/client", "@prisma/adapter-pg", "pg"]
turbopack: {}           // solo dev

images.remotePatterns:
  - avatars.githubusercontent.com
  - lh3.googleusercontent.com
  - randomuser.me
```

---

## Script di Build

```bash
pnpm dev              # Dev server (Turbopack)
pnpm build            # Full build: widget + ContentLayer + Next.js
pnpm build:widget     # Solo widget Preact (output: public/widget.js)
pnpm build:content    # Solo ContentLayer (output: .contentlayer/)
pnpm start            # Avvia build di produzione
pnpm email            # Dev server email templates su :3333
pnpm prisma generate  # Rigenera Prisma client (auto in postinstall)
pnpm prisma migrate dev --name <name>  # Nuova migrazione
```

---

## Database Migrations

Le migrazioni sono in `prisma/migrations/`. Il deploy di nuove migrazioni in produzione:

```bash
pnpm prisma migrate deploy
```

**Non** usare `migrate dev` in produzione. `migrate deploy` applica solo le migrazioni pending senza creare nuove.

---

## TypeScript Config

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "strict": false,
    "strictNullChecks": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./*"],
      "contentlayer/generated": ["./.contentlayer/generated"]
    },
    "moduleResolution": "bundler"
  }
}
```

Alias `@/` mappa alla root del progetto. Usato ovunque per import assoluti.
