import Pusher from "pusher";

import { env } from "@/env.mjs";

let pusherServerInstance: Pusher | null = null;

// Two supported real-time backends:
//  - Pusher Cloud: set PUSHER_APP_ID/SECRET + NEXT_PUBLIC_PUSHER_KEY/CLUSTER
//  - Self-hosted Soketi (Pusher-protocol-compatible): additionally set
//    PUSHER_HOST (+ optionally PUSHER_PORT / PUSHER_USE_TLS). When
//    PUSHER_HOST is set it takes priority over NEXT_PUBLIC_PUSHER_CLUSTER.
export function getPusherServer(): Pusher | null {
  if (!env.PUSHER_APP_ID || !env.PUSHER_SECRET || !env.NEXT_PUBLIC_PUSHER_KEY) {
    return null;
  }

  if (!env.PUSHER_HOST && !env.NEXT_PUBLIC_PUSHER_CLUSTER) {
    return null;
  }

  if (!pusherServerInstance) {
    pusherServerInstance = env.PUSHER_HOST
      ? new Pusher({
          appId: env.PUSHER_APP_ID,
          key: env.NEXT_PUBLIC_PUSHER_KEY,
          secret: env.PUSHER_SECRET,
          host: env.PUSHER_HOST,
          port: env.PUSHER_PORT ?? "6001",
          useTLS: env.PUSHER_USE_TLS === "true",
        })
      : new Pusher({
          appId: env.PUSHER_APP_ID,
          key: env.NEXT_PUBLIC_PUSHER_KEY,
          secret: env.PUSHER_SECRET,
          cluster: env.NEXT_PUBLIC_PUSHER_CLUSTER as string,
          useTLS: true,
        });
  }

  return pusherServerInstance;
}
