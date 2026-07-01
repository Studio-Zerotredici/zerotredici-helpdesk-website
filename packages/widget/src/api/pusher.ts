import { messages, conversationId, visitorToken, isTyping, type Message } from "../stores/state";

let pusherInstance: any = null;
let currentChannel: any = null;

export async function initPusher(
  key: string,
  cluster: string | null | undefined,
  authEndpoint: string,
  host?: string | null,
  port?: string | null,
  forceTLS = true,
) {
  // Dynamically load pusher-js to keep bundle small when not using real-time
  const { default: Pusher } = await import("pusher-js");

  const authOptions = {
    channelAuthorization: {
      endpoint: authEndpoint,
      transport: "ajax" as const,
      headers: {
        "x-visitor-token": visitorToken.value ?? "",
      },
    },
  };

  // Self-hosted Soketi (host given) vs Pusher Cloud (cluster given)
  pusherInstance = host
    ? new Pusher(key, {
        // pusher-js types `cluster` as required even though it's ignored
        // whenever `wsHost` is set (self-hosted Soketi).
        cluster: "",
        wsHost: host,
        wsPort: Number(port ?? "80"),
        wssPort: Number(port ?? "443"),
        forceTLS,
        enabledTransports: ["ws", "wss"],
        disableStats: true,
        ...authOptions,
      })
    : new Pusher(key, {
        cluster: cluster as string,
        ...authOptions,
      });

  return pusherInstance;
}

export function subscribeToConversation() {
  if (!pusherInstance || !conversationId.value) return;

  // Unsubscribe previous
  if (currentChannel) {
    currentChannel.unbind_all();
    pusherInstance.unsubscribe(currentChannel.name);
  }

  const channelName = `presence-visitor-${conversationId.value}`;
  currentChannel = pusherInstance.subscribe(channelName);

  currentChannel.bind("message:created", (data: Message) => {
    if (!messages.value.some((m) => m.id === data.id)) {
      messages.value = [...messages.value, data];
    }
  });

  currentChannel.bind("typing:start", () => {
    isTyping.value = true;
  });

  currentChannel.bind("typing:stop", () => {
    isTyping.value = false;
  });
}

export function isConnected(): boolean {
  return !!pusherInstance;
}

export function disconnect() {
  if (currentChannel) {
    currentChannel.unbind_all();
    pusherInstance?.unsubscribe(currentChannel.name);
    currentChannel = null;
  }
  if (pusherInstance) {
    pusherInstance.disconnect();
    pusherInstance = null;
  }
}
