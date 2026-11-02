// Test fixtures shaped like the Rails serializers, shared by the Insights,
// Reports, chat setup and integrations page tests.
import type { Standup } from "../../../api/types";
import { standupFixture } from "../../../test/fixtures";
import type { ChatResult, ChatSetupPayload, ChatStatus, IntegrationsPayload } from "../../../api/types/chat";
import type { InsightsPayload, ReportPayload } from "../../../api/types/insights";

export { standupFixture };

export function insightsFixture(overrides: Partial<InsightsPayload["insights"]> = {}, standup: Partial<Standup> = {}): InsightsPayload {
  return {
    standup: standupFixture(standup),
    csv_path: "/api/standups/7/analytics.csv?end_date=2026-10-31&start_date=2026-10-02",
    insights: {
      range: {
        start_date: "2026-10-02",
        end_date: "2026-10-31",
        days: 30,
        label: "Oct 2 – Oct 31, 2026",
        limited: false,
        max_days: 365,
        presets: [
          { days: 7, label: "7 days", start_date: "2026-10-25", end_date: "2026-10-31", selected: false },
          { days: 30, label: "30 days", start_date: "2026-10-02", end_date: "2026-10-31", selected: true },
          { days: 90, label: "90 days", start_date: "2026-08-03", end_date: "2026-10-31", selected: false },
        ],
      },
      has_data: true,
      stats: {
        completion_rate: 75,
        previous_completion_rate: 70,
        completion_rate_delta: 5,
        completion_rate_delta_direction: "up",
        comparison_label: "vs. the previous 30 days",
        completed_responses: 6,
        expected_responses: 8,
        active_participants: 2,
        average_response_time_minutes: 12.4,
        average_response_time_label: "12 min",
        runs_count: 2,
      },
      runs: [
        { date: "2026-10-29", expected: 4, completed: 3, skipped: 0, pending: 0, missed: 1, completion_rate: 75 },
        { date: "2026-10-30", expected: 4, completed: 3, skipped: 1, pending: 0, missed: 0, completion_rate: 75 },
      ],
      runs_have_pending: false,
      completion_series: [
        { date: "2026-10-29", label: "Oct 29", value: 75, title: "October 29, 2026: 75% (3/4)" },
        { date: "2026-10-30", label: "Oct 30", value: 75, title: "October 30, 2026: 75% (3/4)" },
      ],
      participants: [
        {
          platform_user_id: "U2",
          display_name: "Jane Smith",
          avatar_url: null,
          completed: 1,
          expected: 2,
          missed: 1,
          completion_rate: 50,
          average_response_time_minutes: 20,
          last_response_at: "2026-10-30T09:40:00Z",
          name: "Jane Smith",
          missed_label: "1 missed response",
          rate_tone: "warning",
          has_expected: true,
        },
        {
          platform_user_id: "U1",
          display_name: "Alex Doe",
          avatar_url: null,
          completed: 2,
          expected: 2,
          missed: 0,
          completion_rate: 100,
          average_response_time_minutes: 5,
          last_response_at: "2026-10-30T09:35:00Z",
          name: "Alex Doe",
          missed_label: "No misses",
          rate_tone: "success",
          has_expected: true,
        },
      ],
      blocker_keywords: [
        { keyword: "deploy", count: 3 },
        { keyword: "review", count: 2 },
      ],
      question_funnel: {
        started: 4,
        started_label: "Out of 4 check-ins started in this period",
        biggest_drop: { position: 3, question: "Any blockers?", drop_off: 1 },
        rows: [
          { position: 1, question: "What did you do yesterday?", started: 4, answered: 4, skipped: 0, not_reached: 0, drop_off: 0, answer_rate: 100 },
          { position: 2, question: "What will you do today?", started: 4, answered: 3, skipped: 1, not_reached: 0, drop_off: 0, answer_rate: 75 },
          { position: 3, question: "Any blockers?", started: 4, answered: 2, skipped: 1, not_reached: 1, drop_off: 1, answer_rate: 50 },
        ],
      },
      question_summaries: [
        {
          question: "What did you do yesterday?",
          responses: 4,
          answered: 4,
          skipped: 0,
          answer_rate: 100,
          common_keywords: [{ keyword: "bugs", count: 2 }],
          latest_answers: [
            { platform_user_id: "U1", display_name: "Alex Doe", answer: "Fixed bugs", submitted_at: "2026-10-30T09:35:00Z", answered_at: "2026-10-30T09:35:00Z", answered_at_label: "Oct 30" },
          ],
        },
        {
          question: "Any blockers?",
          responses: 3,
          answered: 0,
          skipped: 3,
          answer_rate: 0,
          common_keywords: [],
          latest_answers: [],
        },
      ],
      ...overrides,
    },
  };
}

export function reportFixture(overrides: Partial<ReportPayload> = {}): ReportPayload {
  return {
    standup: standupFixture(),
    report_configuration: {
      id: 3,
      persisted: true,
      delivery_channel: "C0123",
      recipients: ["U9"],
      recipients_text: "U9",
      recipients_label: "U9",
      report_format: "slack",
      report_format_label: "Slack message",
      detail_level: "detailed",
      detail_level_label: "Detailed",
      updated_at: "2026-10-30T09:00:00Z",
    },
    options: {
      report_formats: [
        { value: "slack", label: "Slack message" },
        { value: "markdown", label: "Markdown" },
      ],
      detail_levels: [
        { value: "summary", label: "Summary" },
        { value: "detailed", label: "Detailed" },
      ],
    },
    copy: {
      delivery_channel_placeholder: "daily-standup or C0123",
      delivery_channel_hint: "Channel name or ID, without spaces.",
      recipients_placeholder: "One Slack user or channel ID per line",
      recipients_hint: "Optional. Slack user IDs get a DM; channel IDs get a post.",
    },
    report_generations: [
      {
        id: 11,
        status: "completed",
        status_label: "Completed",
        status_tone: "success",
        failed: false,
        standup_date: "2026-10-30",
        requested_at: "2026-10-30T17:00:00Z",
        started_at: "2026-10-30T17:00:01Z",
        completed_at: "2026-10-30T17:00:05Z",
        actor: { id: 1, name: "Maya Manager" },
        requested_by_label: "by Maya Manager",
        delivery_channel: "C0123",
        recipients: [],
        report_format: "slack",
        detail_level: "detailed",
        detail_level_label: "Detailed",
        error_message: null,
        response_count: 3,
        delivery_count: 1,
        result_label: "3 responses to 1 destination",
      },
      {
        id: 10,
        status: "failed",
        status_label: "Failed",
        status_tone: "danger",
        failed: true,
        standup_date: "2026-10-29",
        requested_at: "2026-10-29T17:00:00Z",
        started_at: null,
        completed_at: null,
        actor: null,
        requested_by_label: "Scheduled",
        delivery_channel: "C0123",
        recipients: [],
        report_format: "slack",
        detail_level: "summary",
        detail_level_label: "Summary",
        error_message: "channel_not_found",
        response_count: null,
        delivery_count: null,
        result_label: "channel_not_found",
      },
    ],
    summary: { period_days: 30, completion_rate: 75, completed_responses: 6, expected_responses: 8 },
    ...overrides,
  };
}

export function connectionResult(overrides: Partial<ChatResult> = {}): ChatResult {
  return {
    status: "ok",
    success: true,
    message: "Slack API authentication succeeded.",
    action: null,
    error_code: null,
    metadata: [
      { key: "team", label: "Team", value: "Acme" },
      { key: "user", label: "User", value: "standup-bot" },
    ],
    records: null,
    ...overrides,
  };
}

export function chatStatusFixture(overrides: Partial<ChatStatus> = {}): ChatStatus {
  return {
    platform: "slack",
    label: "Slack",
    title: "Slack app status",
    status: "ok",
    configured: true,
    status_label: "Connected",
    status_tone: "success",
    installation: { status: "configured", message: "The Slack app is installed." },
    credentials: [
      { key: "bot_token", label: "Bot token", configured: true, required: true, message: "SLACK_BOT_TOKEN is set.", state_label: "Configured", tone: "success" },
      { key: "signing_secret", label: "Signing secret", configured: false, required: true, message: "Set SLACK_SIGNING_SECRET.", state_label: "Missing", tone: "warning" },
      { key: "client_id", label: "Client ID", configured: false, required: false, message: "Needed for Slack sign-in.", state_label: "Missing", tone: null },
    ],
    health: null,
    connection: connectionResult(),
    ...overrides,
  };
}

export function channelResult(overrides: Partial<ChatResult> = {}): ChatResult {
  return {
    status: "ok",
    success: true,
    message: "Found 2 Slack channel(s).",
    action: null,
    error_code: null,
    metadata: null,
    records: [
      { id: "C111", kind: "channel", label: "general", name: "general", tz: null, email: null, is_private: false, is_member: true, avatar_url: null, detail: "C111 · bot is a member" },
      { id: "C222", kind: "channel", label: "eng-standup", name: "eng-standup", tz: null, email: null, is_private: true, is_member: false, avatar_url: null, detail: "C222 · private" },
    ],
    ...overrides,
  };
}

export function userResult(overrides: Partial<ChatResult> = {}): ChatResult {
  return {
    status: "ok",
    success: true,
    message: "Found 1 Slack user(s).",
    action: null,
    error_code: null,
    metadata: null,
    records: [
      { id: "U777", kind: "user", label: "Priya Patel", name: "priya", tz: "Europe/London", email: "priya@example.com", is_private: false, is_member: false, avatar_url: null, detail: "U777 · @priya · Europe/London" },
    ],
    ...overrides,
  };
}

export function chatSetupFixture(overrides: Partial<ChatSetupPayload> = {}): ChatSetupPayload {
  return {
    standup: standupFixture(),
    platform: { key: "slack", label: "Slack", icon: "hash" },
    channel: { platform_channel: "C0123", platform_channel_name: "#standup", channel_reference: "#standup (C0123)" },
    copy: {
      channel_id_placeholder: "Channel ID, like C0123",
      channel_search_placeholder: "Search channels by name or ID",
    },
    integration_status: chatStatusFixture(),
    channel_query: null,
    channel_result: null,
    ...overrides,
  };
}

export function integrationsFixture(overrides: Partial<IntegrationsPayload> = {}): IntegrationsPayload {
  return {
    platform: "slack",
    platforms: [
      { key: "slack", label: "Slack", icon: "hash", configured: true, status_label: "Connected", status_tone: "success" },
      { key: "teams", label: "Microsoft Teams", icon: "people", configured: false, status_label: "Not set up", status_tone: "warning" },
    ],
    integration_status: chatStatusFixture(),
    copy: { channel_search_placeholder: "Search channels by name or ID", user_search_placeholder: "Search by name, @username, or ID" },
    standups: [
      { id: 7, name: "Daily standup", active: true, platform: "slack", platform_label: "Slack", platform_channel: "C0123", channel_reference: "#standup (C0123)" },
      { id: 8, name: "Retro", active: false, platform: "slack", platform_label: "Slack", platform_channel: "C0456", channel_reference: "C0456" },
    ],
    channel_query: null,
    user_query: null,
    channel_result: null,
    user_result: null,
    ...overrides,
  };
}
