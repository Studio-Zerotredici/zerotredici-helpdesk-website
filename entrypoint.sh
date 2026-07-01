#!/bin/sh
# entrypoint.sh — runs on every container start.
#
# Applies pending Prisma migrations (idempotent: `migrate deploy` only runs
# migrations that haven't been applied yet, safe to run on every boot) then
# hands off to the Next.js standalone server. This keeps the migration step
# baked into the deployable artifact instead of a manual post-deploy step —
# see .claude/context/deployment.md for the rationale.
set -e

echo "[entrypoint] Applying Prisma migrations..."
node /opt/prisma-cli/node_modules/prisma/build/index.js migrate deploy --schema=/app/prisma/schema.prisma

echo "[entrypoint] Starting GudDesk..."
exec node server.js
