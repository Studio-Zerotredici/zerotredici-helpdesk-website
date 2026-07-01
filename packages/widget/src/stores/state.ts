import { signal, computed } from "@preact/signals";

export interface Message {
  id: string;
  body: string;
  type: "VISITOR" | "AGENT" | "BOT" | "SYSTEM";
  senderName: string | null;
  createdAt: string;
  _sending?: boolean; // optimistic flag — client only
}

export interface WidgetConfig {
  primaryColor: string;
  position: string;
  welcomeMessage: string;
  workspaceName: string | null;
  showBranding: boolean;
  requireEmail: boolean;
  pusherKey: string | null;
  pusherCluster: string | null;
  pusherHost: string | null;
  pusherPort: string | null;
  pusherForceTLS: boolean;
  offlineFormTimeout: number | null; // minutes — null means disabled
  pageVisibilityMode: "exclude" | "include";
  pageVisibilityPatterns: string[];
}

// Core state
export const isOpen = signal(false);
export const isLoading = signal(false);
export const messages = signal<Message[]>([]);
export const conversationId = signal<string | null>(null);
export const visitorId = signal<string | null>(null);
export const visitorToken = signal<string | null>(null);
export const visitorEmail = signal<string | null>(null);
export const inputText = signal("");
export const isTyping = signal(false);
export const showOfflineForm = signal(false);

export const config = signal<WidgetConfig>({
  primaryColor: "#3ECF8E",
  position: "bottom-right",
  welcomeMessage: "Hi! How can we help you?",
  workspaceName: null,
  showBranding: true,
  requireEmail: false,
  pusherKey: null,
  pusherCluster: null,
  pusherHost: null,
  pusherPort: null,
  pusherForceTLS: true,
  offlineFormTimeout: null,
  pageVisibilityMode: "exclude",
  pageVisibilityPatterns: [],
});

export const configLoaded = signal(false);

// Derived
export const needsEmail = computed(
  () => config.value.requireEmail && !visitorEmail.value && !conversationId.value,
);

export const hasConversation = computed(() => !!conversationId.value);

// Persistence helpers
const STORAGE_KEY = "guddesk_state";

export function persistState() {
  try {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        conversationId: conversationId.value,
        visitorId: visitorId.value,
        visitorToken: visitorToken.value,
        visitorEmail: visitorEmail.value,
      }),
    );
  } catch {
    // localStorage unavailable
  }
}

export function restoreState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const data = JSON.parse(raw);
    if (data.conversationId) conversationId.value = data.conversationId;
    if (data.visitorId) visitorId.value = data.visitorId;
    if (data.visitorToken) visitorToken.value = data.visitorToken;
    if (data.visitorEmail) visitorEmail.value = data.visitorEmail;
  } catch {
    // corrupted or unavailable
  }
}

export function clearState() {
  conversationId.value = null;
  visitorId.value = null;
  visitorToken.value = null;
  visitorEmail.value = null;
  messages.value = [];
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}
