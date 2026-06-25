FROM node:20.18-alpine AS base
RUN npm install -g pnpm@10.32.1

# ── Stage: deps ──────────────────────────────────────────────────────────────
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml prisma.config.ts ./
COPY prisma ./prisma
RUN pnpm install --frozen-lockfile

# ── Stage: builder ───────────────────────────────────────────────────────────
FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
# Placeholder values to satisfy env validation at build time.
# Real values are injected at runtime via docker-compose env_file.
ENV AUTH_SECRET=build-time-placeholder
ENV DATABASE_URL=postgresql://placeholder:placeholder@localhost:5432/placeholder
ENV NEXT_PUBLIC_APP_URL=http://localhost:3000

# Build the embeddable widget (self-contained npm install inside packages/widget)
RUN cd packages/widget && pnpm install && pnpm run build && \
    cp dist/guddesk.umd.cjs ../../public/widget.js

# Generate Prisma client for the target platform
RUN pnpm prisma generate

# Build static content (ContentLayer) then Next.js
RUN pnpm run build:content && pnpm exec next build

# ── Stage: runner ────────────────────────────────────────────────────────────
FROM node:20.18-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
