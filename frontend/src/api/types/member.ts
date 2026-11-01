// Member ("/me") payloads: app/serializers/member_*_serializer.rb.
import type { PlatformKey, Tone } from "../types";

/** MemberProfileSerializer. */
export interface MemberProfile {
  platform: PlatformKey;
  platform_label: string;
  platform_user_id: string;
  name: string;
  avatar_url: string | null;
}

export interface MemberNextCheckIn {
  at: string;
  standup_id: number;
  standup_name: string;
  date_label: string;
  time_label: string;
}

export interface MemberStandupsStats {
  standups_count: number;
  active_count: number;
  period_days: number;
  expected: number;
  completed: number;
  completion_rate: number | null;
  next_check_in: MemberNextCheckIn | null;
  status_label: string;
  status_detail: string;
}

export interface MemberResponseStatus {
  id: number;
  status: string;
  status_label: string;
  status_tone: Tone;
}

export interface MemberStandupSummary {
  standup: {
    id: number;
    name: string;
    active: boolean;
    platform: PlatformKey;
    platform_label: string;
    platform_channel: string | null;
    platform_channel_name: string | null;
    channel_reference: string | null;
    schedule_summary: string;
  };
  participant: {
    id: number;
    active: boolean;
    vacation_until: string | null;
  };
  status_label: string;
  status_tone: Tone;
  away: boolean;
  next_check_in: string | null;
  next_check_in_label: string | null;
  today: MemberResponseStatus | null;
  completion_rate: number | null;
  completion_rate_tone: Tone;
  stats: { expected: number; completed: number; missed: number } | null;
  teammates: { name: string; avatar_url: string | null }[];
}

/** GET /api/me/standups */
export interface MemberStandupsPayload {
  member: MemberProfile;
  away_until: string | null;
  away_until_label: string | null;
  stats: MemberStandupsStats;
  standups: MemberStandupSummary[];
}

export interface MemberAnswer {
  question: string;
  answer: string | null;
}

export interface MemberResponse {
  id: number;
  standup_id: number;
  standup_name: string;
  date: string;
  date_label: string;
  status: string;
  status_label: string;
  status_tone: Tone;
  answers: MemberAnswer[];
  created_at: string | null;
  updated_at: string | null;
}

/** GET /api/me/responses?standup_id= */
export interface MemberResponsesPayload {
  member: MemberProfile;
  standups: { id: number; name: string }[];
  standup: { id: number; name: string } | null;
  responses: MemberResponse[];
  limit: number;
  limited: boolean;
}

export interface MemberAwayEntry {
  participant_id: number;
  standup_id: number;
  standup_name: string;
  vacation_until: string;
  vacation_until_label: string;
}

export interface MemberAvailabilityStandup {
  participant_id: number;
  standup_id: number;
  standup_name: string;
  selected: boolean;
}

/** GET/PATCH /api/me/availability, DELETE /api/me/availability/clear */
export interface MemberAvailabilityPayload {
  member: MemberProfile;
  today: string;
  min_date: string;
  max_date: string;
  max_away_days: number;
  away: MemberAwayEntry[];
  standups: MemberAvailabilityStandup[];
  notice?: string;
}

/** PATCH /api/me/availability body. */
export interface MemberAvailabilityParams {
  away_until: string;
  standup_ids: number[];
}
