import PusherClient from "pusher-js";

let pusherClientInstance: PusherClient | null = null;

// Two supported real-time backends — see lib/pusher-server.ts.
// Self-hosted Soketi: set NEXT_PUBLIC_PUSHER_HOST (+ optionally
// NEXT_PUBLIC_PUSHER_PORT / NEXT_PUBLIC_PUSHER_FORCE_TLS). This must be a
// publicly reachable hostname (e.g. ws.yourdomain.com) since it's used
// directly by visitors' browsers on the embedded widget.
export function getPusherClient(): PusherClient | null {
  const key = process.env.NEXT_PUBLIC_PUSHER_KEY;
  const cluster = process.env.NEXT_PUBLIC_PUSHER_CLUSTER;
  const wsHost = process.env.NEXT_PUBLIC_PUSHER_HOST;

  if (!key || (!cluster && !wsHost)) {
    return null;
  }

  if (!pusherClientInstance) {
    pusherClientInstance = wsHost
      ? new PusherClient(key, {
          // pusher-js types `cluster` as required even though it's ignored
          // whenever `wsHost` is set (self-hosted Soketi).
          cluster: "",
          wsHost,
          wsPort: Number(process.env.NEXT_PUBLIC_PUSHER_PORT ?? "80"),
          wssPort: Number(process.env.NEXT_PUBLIC_PUSHER_PORT ?? "443"),
          forceTLS: process.env.NEXT_PUBLIC_PUSHER_FORCE_TLS !== "false",
          enabledTransports: ["ws", "wss"],
          disableStats: true,
          channelAuthorization: {
            endpoint: "/api/pusher/auth",
            transport: "ajax",
          },
        })
      : new PusherClient(key, {
          cluster: cluster as string,
          channelAuthorization: {
            endpoint: "/api/pusher/auth",
            transport: "ajax",
          },
        });
  }

  return pusherClientInstance;
}
