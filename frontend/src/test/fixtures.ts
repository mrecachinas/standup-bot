import type { Bootstrap, Platform } from "../api/types";

export const slackPlatform: Platform = {
  key: "slack",
  label: "Slack",
  icon: "hash",
  enabled: true,
  sign_in_enabled: true,
  user_id_hint: "Slack user ID",
  copy: {},
};

export const teamsPlatform: Platform = {
  key: "teams",
  label: "Microsoft Teams",
  icon: "people",
  enabled: true,
  sign_in_enabled: true,
  user_id_hint: "Entra object ID",
  copy: {},
};

export function signedOutBootstrap(overrides: Partial<Bootstrap> = {}): Bootstrap {
  return {
    authenticated: false,
    user: null,
    member: null,
    sidebar_standups: [],
    platforms: [slackPlatform, teamsPlatform],
    csrf_token: "csrf-signed-out",
    flash: [],
    dev_prefill: null,
    ...overrides,
  };
}

export function userBootstrap({ admin = false, ...overrides }: Partial<Bootstrap> & { admin?: boolean } = {}): Bootstrap {
  return signedOutBootstrap({
    authenticated: true,
    user: { id: 1, name: "Maya Manager", email: "maya@example.com", role: admin ? "admin" : "manager", admin, avatar_url: null },
    sidebar_standups: [
      { id: 7, name: "Daily standup", active: true },
      { id: 8, name: "Retro", active: false },
    ],
    csrf_token: "csrf-user",
    ...overrides,
  });
}

export function memberBootstrap(overrides: Partial<Bootstrap> = {}): Bootstrap {
  return signedOutBootstrap({
    authenticated: true,
    member: { platform: "slack", platform_user_id: "U123", name: "Sam Member", avatar_url: null },
    csrf_token: "csrf-member",
    ...overrides,
  });
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
