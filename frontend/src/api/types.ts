// Shapes returned by the Rails JSON API. Keys are snake_case, as the API sends them.

export type PlatformKey = "slack" | "teams";

export type FlashType = "success" | "danger" | "warning";

export interface FlashMessage {
  type: FlashType;
  message: string;
}

export interface SessionUser {
  id: number;
  name: string;
  email: string;
  role: string;
  admin: boolean;
  avatar_url: string | null;
}

export interface SessionMember {
  platform: PlatformKey;
  platform_user_id: string;
  name: string;
  avatar_url: string | null;
}

export interface SidebarStandup {
  id: number;
  name: string;
  active: boolean;
}

export interface Platform {
  key: PlatformKey;
  label: string;
  icon: "hash" | "people";
  enabled: boolean;
  sign_in_enabled: boolean;
  user_id_hint: string;
  copy: Record<string, string>;
}

export interface DevPrefill {
  email: string | null;
  access_token: string | null;
}

/** GET /api/session, POST /api/session (201) and DELETE /api/session. */
export interface Bootstrap {
  authenticated: boolean;
  user: SessionUser | null;
  member: SessionMember | null;
  sidebar_standups: SidebarStandup[];
  platforms: Platform[];
  csrf_token: string;
  flash: FlashMessage[];
  dev_prefill: DevPrefill | null;
}

export interface SignInParams {
  email: string;
  access_token: string;
}

/** Error bodies: `{ error }` or `{ errors, field_errors }`. */
export interface ApiErrorBody {
  error?: string;
  errors?: string[];
  field_errors?: Record<string, string[]>;
}

/**
 * A standup as app/serializers/standup_serializer.rb returns it. Loosely typed
 * (optional console/count fields) so pages can pass partial payloads.
 */
export interface Standup {
  id: number;
  name: string;
  platform: PlatformKey;
  platform_channel: string | null;
  intro?: string | null;
  outro?: string | null;
  questions?: string[];
  schedule_type?: string;
  schedule_days?: (number | string)[];
  default_hour?: number | null;
  default_minute?: number | null;
  respect_timezone: boolean;
  active: boolean;
  created_at?: string | null;
  updated_at?: string | null;
  participants_count?: number;
  active_participants_count?: number;
  responses_count?: number;
  platform_label?: string;
  platform_channel_name?: string | null;
  reminder_enabled?: boolean;
  reminder_after_minutes?: number | null;
  max_reminders?: number | null;
  send_time?: string;
  schedule_summary?: string;
  schedule_sentence?: string;
  schedule_picker?: { frequency: string; days: number[]; monthly_day?: number };
}

/** success, info, warning, danger, or null for a neutral badge (UiFormat.status_tone). */
export type Tone = "success" | "info" | "warning" | "danger" | null;
