import type { Bootstrap, Participant, Platform, Standup } from "../api/types";

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

/** A standup as StandupSerializer returns it (with counts). */
export function standupFixture(overrides: Partial<Standup> = {}): Standup {
  return {
    id: 7,
    name: "Daily standup",
    platform: "slack",
    platform_channel: "C0123",
    intro: "Morning!",
    outro: "Thanks!",
    questions: ["What did you do yesterday?", "What will you do today?", "Any blockers?"],
    schedule_type: "weekly",
    schedule_days: [1, 2, 3, 4, 5],
    default_hour: 9,
    default_minute: 30,
    respect_timezone: true,
    active: true,
    created_at: "2026-09-01T09:00:00Z",
    updated_at: "2026-10-01T09:00:00Z",
    participants_count: 3,
    active_participants_count: 3,
    responses_count: 42,
    platform_label: "Slack",
    platform_channel_name: "#standup",
    reminder_enabled: true,
    reminder_after_minutes: 60,
    max_reminders: 2,
    send_time: "9:30 AM",
    schedule_summary: "Weekdays at 9:30 AM",
    schedule_sentence: "Weekdays at 9:30 AM, in each person's local time",
    schedule_picker: { frequency: "weekly", days: [1, 2, 3, 4, 5] },
    status_label: "Active",
    status_tone: "success",
    channel_label: "standup",
    timezone_label: "Participant timezones",
    ...overrides,
  };
}

/** A participant as ParticipantSerializer returns it. */
export function participantFixture(overrides: Partial<Participant> = {}): Participant {
  return {
    id: 11,
    standup_id: 7,
    platform_user_id: "U123456",
    display_name: "John Doe",
    active: true,
    cached_timezone: "America/New_York",
    created_at: "2026-09-01T12:00:00Z",
    updated_at: "2026-10-01T12:00:00Z",
    avatar_url: null,
    vacation_until: null,
    timezone_cache_status: "fresh",
    timezone_cache_status_description: "Synced from Slack",
    ...overrides,
  };
}
