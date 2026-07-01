import { createEnv } from "@t3-oss/env-nextjs"
import { z } from "zod"

export const env = createEnv({
  emptyStringAsUndefined: true,
  server: {
    // This is optional because it's only used in development.
    // See https://next-auth.js.org/deployment.
    NEXTAUTH_URL: z.string().url().optional(),
    AUTH_SECRET: z.string().min(1),
    GOOGLE_CLIENT_ID: z.string().min(1).optional(),
    GOOGLE_CLIENT_SECRET: z.string().min(1).optional(),
    DATABASE_URL: z.string().min(1),
    RESEND_API_KEY: z.string().min(1).optional(),
    // Email "from" / reply-to — must be a domain verified in Resend.
    // Falls back to Resend's sandbox sender (only deliverable to the
    // Resend account owner) if unset, so local dev keeps working.
    EMAIL_FROM: z.string().optional(),
    EMAIL_REPLY_TO_DOMAIN: z.string().optional(),
    // Pusher (real-time messaging) — Pusher Cloud OR self-hosted Soketi
    PUSHER_APP_ID: z.string().optional(),
    PUSHER_SECRET: z.string().optional(),
    // Set PUSHER_HOST to point at a self-hosted Soketi instance instead of
    // Pusher Cloud. When unset, NEXT_PUBLIC_PUSHER_CLUSTER (Pusher Cloud) is
    // used instead.
    PUSHER_HOST: z.string().optional(),
    PUSHER_PORT: z.string().optional(),
    PUSHER_USE_TLS: z.string().optional(),
    // Anthropic (AI features)
    ANTHROPIC_API_KEY: z.string().optional(),
    // Slack integration
    SLACK_CLIENT_ID: z.string().optional(),
    SLACK_CLIENT_SECRET: z.string().optional(),
  },
  client: {
    NEXT_PUBLIC_APP_URL: z.string().min(1),
    // Pusher (real-time messaging)
    NEXT_PUBLIC_PUSHER_KEY: z.string().optional(),
    NEXT_PUBLIC_PUSHER_CLUSTER: z.string().optional(),
    // Self-hosted Soketi — the publicly reachable websocket host (e.g.
    // ws.yourdomain.com, terminated behind Dokploy's proxy with TLS).
    NEXT_PUBLIC_PUSHER_HOST: z.string().optional(),
    NEXT_PUBLIC_PUSHER_PORT: z.string().optional(),
    NEXT_PUBLIC_PUSHER_FORCE_TLS: z.string().optional(),
    // Microsoft Clarity (analytics)
    NEXT_PUBLIC_CLARITY_PROJECT_ID: z.string().optional(),
  },
  runtimeEnv: {
    NEXTAUTH_URL: process.env.NEXTAUTH_URL,
    AUTH_SECRET: process.env.AUTH_SECRET,
    GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET: process.env.GOOGLE_CLIENT_SECRET,
    DATABASE_URL: process.env.DATABASE_URL,
    RESEND_API_KEY: process.env.RESEND_API_KEY,
    EMAIL_FROM: process.env.EMAIL_FROM,
    EMAIL_REPLY_TO_DOMAIN: process.env.EMAIL_REPLY_TO_DOMAIN,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    PUSHER_APP_ID: process.env.PUSHER_APP_ID,
    PUSHER_SECRET: process.env.PUSHER_SECRET,
    PUSHER_HOST: process.env.PUSHER_HOST,
    PUSHER_PORT: process.env.PUSHER_PORT,
    PUSHER_USE_TLS: process.env.PUSHER_USE_TLS,
    NEXT_PUBLIC_PUSHER_KEY: process.env.NEXT_PUBLIC_PUSHER_KEY,
    NEXT_PUBLIC_PUSHER_CLUSTER: process.env.NEXT_PUBLIC_PUSHER_CLUSTER,
    NEXT_PUBLIC_PUSHER_HOST: process.env.NEXT_PUBLIC_PUSHER_HOST,
    NEXT_PUBLIC_PUSHER_PORT: process.env.NEXT_PUBLIC_PUSHER_PORT,
    NEXT_PUBLIC_PUSHER_FORCE_TLS: process.env.NEXT_PUBLIC_PUSHER_FORCE_TLS,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    SLACK_CLIENT_ID: process.env.SLACK_CLIENT_ID,
    SLACK_CLIENT_SECRET: process.env.SLACK_CLIENT_SECRET,
    NEXT_PUBLIC_CLARITY_PROJECT_ID: process.env.NEXT_PUBLIC_CLARITY_PROJECT_ID,
  },
})
