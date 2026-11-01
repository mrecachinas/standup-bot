// Chat setup (/api/standups/:id/chat_setup) and Integrations (/api/integrations) payloads.
import type { PlatformKey, Standup, Tone } from "../types";

/** One channel or person from a discovery call. */
export interface ChatRecord {
  id: string;
  kind: "user" | "channel";
  label: string;
  name: string | null;
  tz: string | null;
  email: string | null;
  is_private: boolean;
  is_member: boolean;
  avatar_url: string | null;
  /** "C123 · @jane · Europe/London · private" */
  detail: string;
}

/** A chat API call's outcome (connection check, discovery or test message). */
export interface ChatResult {
  status: string;
  success: boolean;
  message: string | null;
  action: string | null;
  error_code: string | null;
  metadata: { key: string; label: string; value: unknown }[] | null;
  records: ChatRecord[] | null;
}

export interface ChatCredential {
  key: string;
  label: string;
  configured: boolean;
  required: boolean;
  message: string | null;
  state_label: string;
  tone: Tone;
}

/** A platform's app status. */
export interface ChatStatus {
  platform: PlatformKey;
  label: string;
  title: string;
  status: string;
  configured: boolean;
  status_label: string;
  status_tone: Tone;
  installation: { status: string; message: string } | null;
  credentials: ChatCredential[];
  health: unknown;
  connection: ChatResult | null;
}

export interface ChatSetupParticipant {
  id: number;
  standup_id: number;
  platform_user_id: string;
  display_name: string | null;
  active: boolean;
  cached_timezone: string | null;
  created_at: string | null;
  updated_at: string | null;
  avatar_url: string | null;
  vacation_until: string | null;
  timezone_cache_status: string | null;
  timezone_cache_status_description: string | null;
}

/** GET /api/standups/:id/chat_setup and every chat_setup write. */
export interface ChatSetupPayload {
  standup: Standup;
  platform: { key: PlatformKey; label: string; icon: "hash" | "people" };
  channel: { platform_channel: string | null; platform_channel_name: string | null; channel_reference: string };
  copy: {
    channel_id_placeholder: string;
    channel_search_placeholder: string;
    user_search_placeholder: string;
    user_placeholder: string;
  };
  integration_status: ChatStatus;
  participants: ChatSetupParticipant[];
  channel_query: string | null;
  user_query: string | null;
  channel_result: ChatResult | null;
  user_result: ChatResult | null;
  notice?: string;
  participant?: ChatSetupParticipant;
  test_message?: ChatResult;
}

export interface IntegrationPlatformTab {
  key: PlatformKey;
  label: string;
  icon: "hash" | "people";
  configured: boolean;
  status_label: string;
  status_tone: Tone;
}

export interface IntegrationStandup {
  id: number;
  name: string;
  active: boolean;
  platform: PlatformKey;
  platform_label: string;
  platform_channel: string | null;
  channel_reference: string;
}

/** GET /api/integrations */
export interface IntegrationsPayload {
  platform: PlatformKey;
  platforms: IntegrationPlatformTab[];
  integration_status: ChatStatus;
  copy: { channel_search_placeholder: string; user_search_placeholder: string };
  standups: IntegrationStandup[];
  channel_query: string | null;
  user_query: string | null;
  channel_result: ChatResult | null;
  user_result: ChatResult | null;
}
