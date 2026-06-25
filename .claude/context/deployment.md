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
- User: `nextjs` (UID 1001, non-root)
- Porta: `3000`
- CMD: `node server.js`

### docker-compose.yml

```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    env_file: .env
    networks:
      - gateway
      - postgres-16

networks:
  gateway:
    external: true   # rete esterna per reverse proxy
  postgres-16:
    external: true   # rete esterna per il database
```

**Nota:** `AUTH_TRUST_HOST=true` è richiesto in produzione quando si usa un reverse proxy (Nginx, Traefik, Caddy).

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

# Database
DATABASE_URL=postgresql://user:password@host:5432/dbname?sslmode=require

# Email
RESEND_API_KEY=re_xxxxx

# Real-time
PUSHER_APP_ID=
PUSHER_SECRET=
NEXT_PUBLIC_PUSHER_KEY=
NEXT_PUBLIC_PUSHER_CLUSTER=eu

# AI
ANTHROPIC_API_KEY=sk-ant-xxxxx
```

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
