// Payloads for a standup's Participants, Schedule and Responses tabs.
import type { Platform, Standup, Tone } from "../types";

// ---- Participants (GET /api/standups/:id/participants?view=console) ----

/** ParticipantSerializer + ParticipantRosterSerializer. */
export interface RosterParticipant {
  id: number;
  standup_id: number;
  platform_user_id: string;
  display_name: string;
  active: boolean;
  cached_timezone: string | null;
  created_at: string | null;
  updated_at: string | null;
  avatar_url: string | null;
  vacation_until: string | null;
  timezone_cache_status: "fresh" | "stale" | "invalid" | "missing";
  timezone_cache_status_description: string;
  status_label: string;
  status_tone: Tone;
  manager: boolean;
  manager_user_id: number | null;
  can_make_manager: boolean;
  can_remove_manager: boolean;
  timezone_label: string;
  timezone_synced: boolean;
  available_today: boolean;
  vacation_status: string;
  holiday_status: string | null;
}

/** ParticipantManagerSerializer. */
export interface StandupManager {
  id: number;
  name: string;
  avatar_url: string | null;
  admin: boolean;
  role_label: string;
  platform_user_id: string | null;
  current_user: boolean;
  can_remove: boolean;
}

export interface ParticipantsConsole {
  participants: RosterParticipant[];
  standup: Standup;
  platform: Platform;
  managers: StandupManager[];
  manager_rules: {
    minimum_managers: number;
    can_remove_managers: boolean;
    only_admins_manage: boolean;
  };
  summary: {
    participant_count: number;
    active_count: number;
    stale_timezone_count: number;
    holiday_today: boolean;
  };
  sync_defaults: {
    channel: string | null;
    channel_name: string | null;
    deactivate_missing: boolean;
  };
}

/** `participant: {...}` for POST/PATCH .../participants. */
export interface ParticipantParams {
  platform_user_id?: string;
  display_name?: string;
  active?: boolean;
  cached_timezone?: string | null;
  vacation_until?: string | null;
}

export interface ParticipantMutationResult {
  participant: RosterParticipant;
  notice: string;
}

export interface ImportSummary {
  created_count: number;
  updated_count: number;
  unchanged_count: number;
  deactivated_count: number;
  error_count: number;
}

/** POST .../participants/bulk_import and .../participants/sync (the 422 body has `errors` and `summary` too). */
export interface ImportResult {
  notice: string;
  summary: ImportSummary | null;
  errors: string[];
}

export interface AddManagerResult {
  manager: StandupManager;
  participant_id: number;
  can_manage: boolean;
  notice: string;
}

export interface RemoveManagerResult {
  can_manage: boolean;
  user_id: number;
  notice: string;
}

// ---- Schedule (GET /api/standups/:id/schedule_exceptions) ----

export type ScheduleExceptionType = "skipped_date" | "holiday" | "cancelled" | "rescheduled";

/** ScheduleExceptionOccurrenceSerializer. */
export interface ScheduleOccurrence {
  standup_date: string;
  standup_date_label: string;
  scheduled_at: string;
  local_date: string;
  local_time: string;
  local_label: string;
  local_short_label: string;
  status: string;
  status_label: string;
  status_tone: Tone;
  sendable: boolean;
  blocked: boolean;
  note: string | null;
  exception_id: number | null;
  can_skip: boolean;
  /** A skipped date that can be put back on the schedule by removing `exception_id`. */
  can_unskip: boolean;
}

/** ScheduleExceptionSerializer. */
export interface ScheduleException {
  id: number;
  standup_id: number;
  exception_type: ScheduleExceptionType;
  label: string;
  tone: Tone;
  blocks_occurrence: boolean;
  original_date: string;
  original_date_label: string;
  rescheduled_date: string | null;
  rescheduled_hour: number | null;
  rescheduled_minute: number | null;
  rescheduled_time: string | null;
  rescheduled_timezone: string | null;
  scheduled_at: string | null;
  scheduled_at_label: string | null;
  reason: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface ScheduleExceptionsPayload {
  standup: Standup;
  preview_timezone: string;
  default_exception_timezone: string;
  time_zone_options: string[];
  exception_type_options: { value: ScheduleExceptionType; label: string }[];
  upcoming_occurrences: ScheduleOccurrence[];
  next_occurrence: ScheduleOccurrence | null;
  schedule_exceptions: ScheduleException[];
  notes: string[];
}

/** `schedule_exception: {...}` for POST .../schedule_exceptions. */
export interface ScheduleExceptionParams {
  exception_type: ScheduleExceptionType;
  original_date: string;
  rescheduled_date?: string;
  rescheduled_time?: string;
  rescheduled_timezone?: string;
  reason?: string;
}

export interface ScheduleExceptionResult {
  schedule_exception: ScheduleException;
  notice: string;
}

// ---- Responses (GET /api/standups/:id/responses?view=history) ----

export interface HistoryFilters {
  start_date: string;
  end_date: string;
  participant: string | null;
  question: string | null;
}

export interface HistoryAnswer {
  question: string;
  text: string | null;
  display_text: string;
  timestamp: string | null;
  answered_at: string | null;
  answered_at_label: string | null;
}

export interface HistoryEntry {
  platform_user_id: string;
  display_name: string;
  avatar_url: string | null;
  expected: boolean;
  answered: boolean;
  missed: boolean;
  /** Expected today or later but not sent yet. */
  upcoming: boolean;
  status: string | null;
  status_label: string;
  status_tone: Tone;
  response_id: number | null;
  submitted_at: string | null;
  submitted_at_label: string | null;
  updated_at: string | null;
  updated_at_label: string | null;
  updated_after_create: boolean;
  answers: HistoryAnswer[];
  empty_message: string | null;
}

export interface HistoryDay {
  date: string;
  date_label: string;
  expected_count: number;
  answered_count: number;
  missed_count: number;
  upcoming_count: number;
  answer_rate: number;
  answer_rate_tone: Tone;
  entries: HistoryEntry[];
}

export interface ResponseHistory {
  filters: HistoryFilters;
  range_limited: boolean;
  max_range_days: number;
  default_range_days: number;
  /** answered + skipped + pending + missed = expected. */
  summary: {
    dates: number;
    expected: number;
    answered: number;
    skipped: number;
    pending: number;
    missed: number;
    answer_rate: number | null;
    answer_rate_tone: Tone;
  };
  participant_options: { platform_user_id: string; display_name: string; label: string; active: boolean }[];
  question_options: string[];
  days: HistoryDay[];
}

export interface ResponsesHistoryPayload {
  standup: Standup;
  history: ResponseHistory;
}
