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

# Prisma CLI (not traced by `next build`'s standalone output, which only
# bundles runtime imports) — needed at container start to run
# `prisma migrate deploy`. Installed fresh into an isolated directory rather
# than copied from the builder stage or added into /app: pnpm's non-hoisted
# node_modules keeps the CLI's own private dependencies (@prisma/engines,
# @prisma/config, ...) as symlinks into node_modules/.pnpm, which a plain
# `COPY` of node_modules/prisma leaves dangling once separated from that
# store — and running `pnpm add` directly in /app (which already has the
# full app package.json but no lockfile) would reinstall the entire
# dependency tree at different resolved versions than the build used.
# A scoped install in its own directory resolves only the CLI's own tree.
# Note: prisma.config.ts is deliberately not referenced here so the CLI
# falls back to the conventional prisma/schema.prisma path instead of
# trying to load dotenv/other build-time-only deps.
RUN npm install -g pnpm@10.32.1 && \
    PRISMA_VERSION=$(node -p "require('/app/package.json').devDependencies.prisma.replace(/^[^0-9]*/, '')") && \
    mkdir -p /opt/prisma-cli && cd /opt/prisma-cli && \
    pnpm init && pnpm add --ignore-scripts "prisma@${PRISMA_VERSION}" && \
    chown -R nextjs:nodejs /opt/prisma-cli

COPY --chown=nextjs:nodejs entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

USER nextjs

EXPOSE 3000

ENTRYPOINT ["./entrypoint.sh"]
