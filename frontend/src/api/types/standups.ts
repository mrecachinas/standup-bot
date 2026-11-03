// Payloads for the standups list, the standup overview and the standup editor
// (app/serializers/overview_dashboard_serializer.rb, standup_overview_serializer.rb,
// standup_form_serializer.rb, standup_schedule_preview_serializer.rb and
// Api::PeopleController).
import type { Participant, Platform, PlatformKey, RunTotals, Standup, Tone } from "../types";

export type Visibility = "all" | "active" | "paused";

// --- GET /api/overview ------------------------------------------------------

export interface OverviewStats {
  standups_count: number;
  active_count: number;
  paused_count: number;
  paused_label: string;
  people_count: number;
  people_label: string;
  expected_responses: number;
  completed_responses: number;
  completion_rate: number | null;
  completion_rate_label: string;
  completion_tone: Tone;
  completion_sub_label: string;
  needs_attention_count: number;
  needs_attention_label: string;
}

export interface NeedsAttentionItem {
  standup_id: number;
  name: string;
  active: boolean;
  reason: string;
  tone: Tone;
}

export interface OverviewStandup extends Standup {
  standup_id: number;
  participant_count: number;
  participant_label: string;
  participant_avatars: { name: string; avatar_url: string | null }[];
  avatar_limit: number;
  completion_rate: number | null;
  completion_rate_label: string | null;
  completion_tone: Tone;
  completed_responses: number;
  expected_responses: number;
  completion_sub_label: string;
  trend_rates: (number | null)[];
  next_run: { scheduled_at: string | null; label: string; title?: string };
  latest_run_status: string;
  latest_run_status_tone: Tone;
  latest_run_summary: string | null;
  latest_run_pending: boolean;
  needs_attention: boolean;
  attention_reason: string | null;
}

export interface OverviewPayload {
  visibility: Visibility;
  visibility_options: { value: Visibility; label: string }[];
  period_days: number;
  subtitle: string;
  empty: boolean;
  empty_list_message: string;
  stats: OverviewStats;
  daily_totals: RunTotals[];
  daily_has_pending: boolean;
  needs_attention: NeedsAttentionItem[];
  needs_attention_empty_message: string;
  standups: OverviewStandup[];
}

/** PATCH /api/standups/:id/pause|resume, POST /api/standups, PATCH /api/standups/:id. */
export interface StandupMutationResult {
  standup: Standup;
  notice: string | null;
}

// --- Schedule previews ------------------------------------------------------

/** A run in a schedule preview, in the preview's time zone. */
export interface PreviewOccurrence {
  scheduled_at: string;
  /** Local date, "2026-11-02". */
  date: string;
  weekday: string;
  time: string;
  label: string;
}

/** POST /api/standups/preview, and the editor's/overview's initial preview. */
export interface SchedulePreview {
  occurrences: PreviewOccurrence[];
  preview_timezone: string;
  error: string | null;
  empty_message: string;
}

// --- GET /api/standups/:id?include=overview ---------------------------------

export interface OverviewResponse {
  id: number;
  platform_user_id: string;
  display_name: string;
  avatar_url: string | null;
  status: string;
  status_label: string;
  status_tone: Tone;
  standup_date: string | null;
  created_at: string | null;
  updated_at: string | null;
  answers: { question: string | null; answer: string | null }[];
}

export interface OverviewParticipant extends Participant {
  timezone_label: string | null;
}

export interface OverviewScheduleException {
  id: number;
  exception_type: string;
  label: string;
  tone: Tone;
  original_date: string | null;
  reason: string | null;
  rescheduled_at: string | null;
  blocks_occurrence: boolean;
}

export interface StandupOverview {
  period_days: number;
  completion: {
    rate: number | null;
    label: string;
    tone: Tone;
    completed: number;
    expected: number;
    sub_label: string;
    previous_rate: number | null;
    delta: { value: number; direction: "up" | "down" | "flat" } | null;
  };
  average_response_time: { minutes: number | null; label: string };
  participant_counts: { total: number; active: number; inactive: number };
  next_run: { scheduled_at: string | null; label: string; sub_label: string };
  runs: RunTotals[];
  runs_have_pending: boolean;
  latest_run: { date: string | null; date_label: string; responses: OverviewResponse[] };
  participants: OverviewParticipant[];
  sidebar_participants: OverviewParticipant[];
  more_participants_count: number;
  upcoming: SchedulePreview & { paused: boolean; paused_message: string | null };
  schedule_exceptions: OverviewScheduleException[];
}

export interface StandupOverviewPayload {
  standup: Standup;
  overview: StandupOverview;
}

// --- GET /api/standups/new and /api/standups/:id/edit -----------------------

export interface StandupTemplate {
  key: string;
  label: string;
  description: string;
  question_count: number;
  meta: string;
}

export interface ChannelField {
  /** "search": Slack's search-as-you-type picker (GET /api/standups/channel_options?query=). */
  input: "select" | "text" | "prefixed_text" | "search";
  value: string | null;
  name: string | null;
  choices: { id: string; label: string }[];
  placeholder: string;
  hint: string | null;
  prefix?: string;
}

/** A channel from GET /api/standups/channel_options. */
export interface ChannelOption {
  id: string;
  label: string;
  name?: string;
  is_private?: boolean;
  is_member?: boolean;
}

/** GET /api/standups/channel_options?platform=…&query=… */
export interface ChannelOptionsPayload {
  platform: string;
  records: ChannelOption[];
  success: boolean;
  message: string | null;
  /** A next step, e.g. why private channels weren't listed. */
  action: string | null;
}

export interface ParticipantRow {
  id: number | null;
  platform_user_id: string;
  original_platform_user_id: string;
  display_name: string | null;
  cached_timezone: string | null;
  avatar_url: string | null;
  active: boolean;
  destroy: boolean;
  label: string;
  pending: boolean;
  meta: string | null;
}

export type Frequency = "weekly" | "biweekly" | "monthly";

/** The editor's standup: unsaved (id null) on the new page. */
export type FormStandup = Omit<Standup, "id"> & { id: number | null };

export interface StandupFormPayload {
  mode: "new" | "edit";
  standup: FormStandup;
  templates: StandupTemplate[];
  template_key: string | null;
  platform: Platform;
  platform_options: Platform[];
  show_platform_picker: boolean;
  platform_locked: boolean;
  channel: ChannelField;
  channel_options: { records: { id: string; label: string }[]; success: boolean; message: string | null } | null;
  question_rows: string[];
  question_suggestions: { text: string; used: boolean }[];
  participant_rows: ParticipantRow[];
  participants_hint: string;
  weekday_options: { value: number; label: string; short_label: string }[];
  day_presets: { label: string; days: number[] }[];
  frequency_options: { value: Frequency; label: string; hint?: string }[];
  respect_timezone_options: { value: boolean; label: string }[];
  monthly_day: number | string;
  send_time: string;
  advanced_open: boolean;
  default_preview_timezone: string | null;
  detect_preview_timezone: boolean;
  preview_timezone: string;
  time_zone_options: { name: string; iana: string }[];
  schedule_preview: SchedulePreview;
  message_preview: { time: string; intro: string | null; question_count: number; first_question: string; hint: string };
}

/** The `standup` params POST /api/standups and PATCH /api/standups/:id take from the console. */
export interface StandupFormParams {
  name: string;
  platform?: PlatformKey;
  platform_channel: string;
  platform_channel_name?: string | null;
  intro: string;
  outro: string;
  reminder_enabled: boolean;
  reminder_after_minutes: string;
  max_reminders: string;
  respect_timezone: boolean;
  send_time: string;
  frequency: Frequency;
  days: number[];
  monthly_day: string;
  question_rows: string[];
  /** New standups only; editing leaves people to the People tab. */
  participants?: {
    id: number | null;
    platform_user_id: string;
    original_platform_user_id: string;
    display_name: string;
    cached_timezone: string;
    active: boolean;
    _destroy: boolean;
  }[];
  participant_handles?: string;
}

// --- GET /api/people --------------------------------------------------------

export interface PersonResult {
  platform_user_id: string;
  display_name: string;
  avatar_url: string | null;
  timezone: string | null;
}

export interface PeopleSearchPayload {
  platform: PlatformKey;
  people: PersonResult[];
  success: boolean;
  message: string | null;
}
