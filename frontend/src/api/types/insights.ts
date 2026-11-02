// Insights (GET /api/standups/:id/analytics?view=insights) and Reports
// (/api/standups/:id/report) payloads.
import type { RunTotals, Standup, Tone } from "../types";

export interface InsightsRangePreset {
  days: number;
  label: string;
  start_date: string;
  end_date: string;
  selected: boolean;
}

export interface InsightsRange {
  start_date: string;
  end_date: string;
  days: number;
  /** "Oct 2 – Oct 31, 2026" */
  label: string;
  limited: boolean;
  max_days: number;
  presets: InsightsRangePreset[];
}

export interface InsightsStats {
  completion_rate: number;
  previous_completion_rate: number | null;
  completion_rate_delta: number | null;
  completion_rate_delta_direction: "up" | "down" | "flat" | null;
  /** "vs. the previous 30 days" */
  comparison_label: string;
  completed_responses: number;
  expected_responses: number;
  active_participants: number;
  average_response_time_minutes: number | null;
  average_response_time_label: string | null;
  runs_count: number;
}

export interface InsightsSeriesPoint {
  date: string;
  label: string;
  value: number;
  title: string;
}

export interface InsightsParticipant {
  platform_user_id: string;
  display_name: string | null;
  avatar_url: string | null;
  completed: number;
  expected: number;
  missed: number;
  completion_rate: number;
  average_response_time_minutes: number | null;
  last_response_at: string | null;
  name: string;
  missed_label: string;
  rate_tone: Tone;
  has_expected: boolean;
}

export interface Keyword {
  keyword: string;
  count: number;
}

export interface QuestionFunnelRow {
  position: number;
  question: string;
  started: number;
  answered: number;
  skipped: number;
  not_reached: number;
  drop_off: number;
  answer_rate: number;
}

export interface QuestionFunnel {
  started: number;
  started_label: string;
  biggest_drop: Pick<QuestionFunnelRow, "position" | "question" | "drop_off"> | null;
  rows: QuestionFunnelRow[];
}

export interface QuestionAnswer {
  platform_user_id: string;
  display_name: string;
  answer: string;
  submitted_at: string | null;
  answered_at: string | null;
  answered_at_label: string | null;
}

export interface QuestionSummary {
  question: string;
  responses: number;
  answered: number;
  skipped: number;
  answer_rate: number;
  common_keywords: Keyword[];
  latest_answers: QuestionAnswer[];
}

export interface Insights {
  range: InsightsRange;
  has_data: boolean;
  stats: InsightsStats;
  runs: RunTotals[];
  runs_have_pending: boolean;
  completion_series: InsightsSeriesPoint[];
  participants: InsightsParticipant[];
  blocker_keywords: Keyword[];
  question_funnel: QuestionFunnel;
  question_summaries: QuestionSummary[];
}

/** GET /api/standups/:id/analytics?view=insights */
export interface InsightsPayload {
  standup: Standup;
  insights: Insights;
  csv_path: string;
}

export interface Option {
  value: string;
  label: string;
}

export interface ReportConfiguration {
  id: number | null;
  persisted: boolean;
  delivery_channel: string | null;
  recipients: string[];
  recipients_text: string | null;
  recipients_label: string;
  report_format: string;
  report_format_label: string | null;
  detail_level: string;
  detail_level_label: string | null;
  updated_at: string | null;
}

export interface ReportGeneration {
  id: number;
  status: string;
  status_label: string;
  status_tone: Tone;
  failed: boolean;
  standup_date: string | null;
  requested_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  actor: { id: number; name: string } | null;
  requested_by_label: string;
  delivery_channel: string | null;
  recipients: string[];
  report_format: string;
  detail_level: string;
  detail_level_label: string | null;
  error_message: string | null;
  response_count: number | null;
  delivery_count: number | null;
  result_label: string | null;
}

/** GET/PATCH /api/standups/:id/report and POST .../report/generate */
export interface ReportPayload {
  standup: Standup;
  report_configuration: ReportConfiguration;
  options: { report_formats: Option[]; detail_levels: Option[] };
  copy: {
    delivery_channel_placeholder: string;
    delivery_channel_hint: string;
    recipients_placeholder: string;
    recipients_hint: string;
  };
  report_generations: ReportGeneration[];
  summary: {
    period_days: number;
    completion_rate: number | null;
    completed_responses: number;
    expected_responses: number;
  };
  notice?: string;
  /** A failed "Send report now" (422) still returns the payload with its error. */
  error?: string;
}

/** PATCH /api/standups/:id/report body. */
export interface ReportConfigurationParams {
  report_configuration: {
    delivery_channel: string;
    recipients_text: string;
    report_format: string;
    detail_level: string;
  };
}
