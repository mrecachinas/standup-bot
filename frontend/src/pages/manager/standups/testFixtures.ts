// Test payloads shaped like the Rails serializers (overview, standup overview, editor).
import type { Standup } from "../../../api/types";
import type { OverviewPayload, OverviewStandup, StandupFormPayload, StandupOverviewPayload } from "../../../api/types/standups";
import { participantFixture, standupFixture as baseStandup, slackPlatform, teamsPlatform } from "../../../test/fixtures";

export function standupFixture(overrides: Partial<Standup> = {}): Standup {
  return baseStandup({
    platform_channel: "eng-standup",
    platform_channel_name: null,
    channel_label: "eng-standup",
    questions: ["What did you do yesterday?", "What will you do today?"],
    schedule_type: "weekdays",
    schedule_days: [],
    created_at: "2026-10-01T09:00:00Z",
    active_participants_count: 2,
    responses_count: 10,
    ...overrides,
  });
}

function overviewStandupFixture(overrides: Partial<OverviewStandup> = {}): OverviewStandup {
  return {
    ...standupFixture(),
    standup_id: 7,
    participant_count: 2,
    participant_label: "2 active participants",
    participant_avatars: [
      { name: "Ada Lovelace", avatar_url: null },
      { name: "Grace Hopper", avatar_url: null },
    ],
    avatar_limit: 4,
    completion_rate: 75,
    completion_rate_label: "75%",
    completion_tone: "success",
    completed_responses: 6,
    expected_responses: 8,
    completion_sub_label: "6 of 8 responses",
    trend_rates: [50, 75, 100],
    next_run: { scheduled_at: "2026-11-02T14:30:00Z", label: "Next in about 22 hours", title: "November 2, 2026 14:30" },
    latest_run_status: "Pending",
    latest_run_status_tone: "info",
    latest_run_summary: "Oct 30 · 1 of 2 answered",
    latest_run_pending: true,
    needs_attention: false,
    attention_reason: null,
    ...overrides,
  };
}

export function overviewFixture(overrides: Partial<OverviewPayload> = {}): OverviewPayload {
  const retro = overviewStandupFixture({
    id: 8,
    standup_id: 8,
    name: "Retro",
    active: false,
    status_label: "Paused",
    channel_label: "retro",
    platform_channel: "retro",
    participant_count: 0,
    participant_label: "None yet",
    participant_avatars: [],
    completion_rate: null,
    completion_rate_label: null,
    completion_tone: null,
    completed_responses: 0,
    expected_responses: 0,
    completion_sub_label: "No runs yet",
    trend_rates: [],
    next_run: { scheduled_at: null, label: "Not scheduled" },
    latest_run_status: "No runs yet",
    latest_run_status_tone: null,
    latest_run_summary: null,
    latest_run_pending: false,
    needs_attention: true,
    attention_reason: "Paused",
  });

  return {
    visibility: "all",
    visibility_options: [
      { value: "all", label: "All" },
      { value: "active", label: "Active" },
      { value: "paused", label: "Paused" },
    ],
    period_days: 14,
    subtitle: "How your standups are doing over the last 14 days.",
    empty: false,
    empty_list_message: "No all standups.",
    stats: {
      standups_count: 2,
      active_count: 1,
      paused_count: 1,
      paused_label: "1 paused",
      people_count: 2,
      people_label: "Across 2 standups",
      expected_responses: 8,
      completed_responses: 6,
      completion_rate: 75,
      completion_rate_label: "75%",
      completion_tone: "success",
      completion_sub_label: "6 of 8 expected",
      needs_attention_count: 1,
      needs_attention_label: "1 paused · 1 under 60%",
    },
    daily_totals: [
      { date: "2026-10-29", expected: 4, completed: 3, skipped: 0, pending: 0, missed: 1, completion_rate: 75 },
      { date: "2026-10-30", expected: 4, completed: 3, skipped: 0, pending: 1, missed: 0, completion_rate: 75 },
    ],
    daily_has_pending: true,
    needs_attention: [{ standup_id: 8, name: "Retro", active: false, reason: "Paused", tone: "warning" }],
    needs_attention_empty_message: "All standups are running and above 60% completion.",
    standups: [overviewStandupFixture(), retro],
    ...overrides,
  };
}

export function standupOverviewFixture(overrides: Partial<StandupOverviewPayload["overview"]> = {}, standup: Partial<Standup> = {}): StandupOverviewPayload {
  return {
    standup: standupFixture(standup),
    overview: {
      period_days: 14,
      completion: {
        rate: 75,
        label: "75%",
        tone: "success",
        completed: 6,
        expected: 8,
        sub_label: "6 of 8 responses",
        previous_rate: 50,
        delta: { value: 25, direction: "up" },
      },
      average_response_time: { minutes: 12, label: "12 minutes" },
      participant_counts: { total: 3, active: 2, inactive: 1 },
      next_run: { scheduled_at: "2026-11-02T14:30:00Z", label: "Mon, Nov 2", sub_label: "9:30 AM in each person's timezone" },
      runs: [{ date: "2026-10-30", expected: 2, completed: 1, skipped: 0, pending: 1, missed: 0, completion_rate: 50 }],
      runs_have_pending: true,
      latest_run: {
        date: "2026-10-30",
        date_label: "October 30, 2026",
        responses: [
          {
            id: 1,
            platform_user_id: "U1",
            display_name: "Ada Lovelace",
            avatar_url: null,
            status: "completed",
            status_label: "Completed",
            status_tone: "success",
            standup_date: "2026-10-30",
            created_at: "2026-10-30T09:40:00Z",
            updated_at: "2026-10-30T09:40:00Z",
            answers: [{ question: "What did you do yesterday?", answer: "Shipped the engine" }],
          },
          {
            id: 2,
            platform_user_id: "U2",
            display_name: "Grace Hopper",
            avatar_url: null,
            status: "pending",
            status_label: "Pending",
            status_tone: "info",
            standup_date: "2026-10-30",
            created_at: null,
            updated_at: null,
            answers: [],
          },
        ],
      },
      participants: [],
      sidebar_participants: [
        { ...participantFixture({ id: 1, platform_user_id: "U1", display_name: "Ada Lovelace", cached_timezone: "Europe/London" }), timezone_label: "London" },
        { ...participantFixture({ id: 2, platform_user_id: "U2", display_name: "Grace Hopper", cached_timezone: "America/New_York" }), timezone_label: "New York" },
      ],
      more_participants_count: 0,
      upcoming: {
        occurrences: [occurrence("2026-11-02", 2, "Monday"), occurrence("2026-11-03", 3, "Tuesday")],
        preview_timezone: "UTC",
        error: null,
        empty_message: "No upcoming runs.",
        paused: false,
        paused_message: null,
      },
      schedule_exceptions: [
        { id: 5, exception_type: "holiday", label: "Holiday", tone: "warning", original_date: "2026-11-26", reason: "Thanksgiving", rescheduled_at: null, blocks_occurrence: true },
      ],
      ...overrides,
    },
  };
}

export function occurrence(date: string, day: number, weekday: string) {
  return {
    scheduled_at: `${date}T09:30:00Z`,
    date,
    weekday,
    time: "9:30 AM UTC",
    label: `${weekday}, November ${day}, 2026 at 9:30 AM UTC`,
  };
}

const TIME_ZONES = [
  { name: "UTC", iana: "Etc/UTC" },
  { name: "Eastern Time (US & Canada)", iana: "America/New_York" },
  { name: "London", iana: "Europe/London" },
];

export function formFixture(overrides: Partial<StandupFormPayload> = {}): StandupFormPayload {
  return {
    mode: "new",
    standup: { ...standupFixture({ name: "", platform_channel: null, intro: null, outro: null }), id: null },
    templates: [
      { key: "daily", label: "Daily standup", description: "Weekdays at 9:30 AM", question_count: 3, meta: "Weekdays at 9:30 AM · 3 questions" },
      { key: "weekly", label: "Weekly check-in", description: "Mondays at 10:00 AM", question_count: 3, meta: "Mondays at 10:00 AM · 3 questions" },
      { key: "retro", label: "Friday retro", description: "Fridays at 3:00 PM", question_count: 3, meta: "Fridays at 3:00 PM · 3 questions" },
    ],
    template_key: "daily",
    platform: { ...slackPlatform, copy: { user_placeholder: "@jane, Jane Doe, or U123ABC" } },
    platform_options: [slackPlatform, teamsPlatform],
    show_platform_picker: true,
    platform_locked: false,
    channel: { input: "prefixed_text", prefix: "#", value: "", name: null, choices: [], placeholder: "eng-standup", hint: null },
    channel_options: null,
    question_rows: ["What did you get done yesterday?", "What are you working on today?", "Is anything blocking you?", ""],
    question_suggestions: [
      { text: "What did you get done yesterday?", used: true },
      { text: "Where could you use help?", used: false },
    ],
    participant_rows: [
      {
        id: null,
        platform_user_id: "U0MAYA",
        original_platform_user_id: "U0MAYA",
        display_name: "Maya Manager",
        cached_timezone: "America/New_York",
        avatar_url: null,
        active: true,
        destroy: false,
        label: "Maya Manager",
        pending: false,
        meta: null,
      },
    ],
    participants_hint: "Names and timezones come from Slack.",
    weekday_options: [
      { value: 1, label: "Monday", short_label: "Mon" },
      { value: 2, label: "Tuesday", short_label: "Tue" },
      { value: 3, label: "Wednesday", short_label: "Wed" },
      { value: 4, label: "Thursday", short_label: "Thu" },
      { value: 5, label: "Friday", short_label: "Fri" },
      { value: 6, label: "Saturday", short_label: "Sat" },
      { value: 0, label: "Sunday", short_label: "Sun" },
    ],
    day_presets: [
      { label: "Weekdays", days: [1, 2, 3, 4, 5] },
      { label: "Every day", days: [0, 1, 2, 3, 4, 5, 6] },
      { label: "Mon, Wed, Fri", days: [1, 3, 5] },
    ],
    frequency_options: [
      { value: "weekly", label: "Every week" },
      { value: "biweekly", label: "Every other week", hint: "Every other week runs on a single day." },
      { value: "monthly", label: "Once a month" },
    ],
    respect_timezone_options: [
      { value: true, label: "Each person's local time" },
      { value: false, label: "The same moment for everyone (UTC)" },
    ],
    monthly_day: 1,
    send_time: "09:30",
    advanced_open: false,
    default_preview_timezone: "Eastern Time (US & Canada)",
    detect_preview_timezone: false,
    preview_timezone: "Eastern Time (US & Canada)",
    time_zone_options: TIME_ZONES,
    schedule_preview: {
      occurrences: [occurrence("2026-11-02", 2, "Monday")],
      preview_timezone: "Eastern Time (US & Canada)",
      error: null,
      empty_message: "Choose a recurrence and send time to see upcoming runs.",
    },
    message_preview: {
      time: "9:30 AM",
      intro: null,
      question_count: 3,
      first_question: "What did you get done yesterday?",
      hint: "Asked one at a time in a Slack DM. Press Enter to add another.",
    },
    ...overrides,
  };
}

export function editFormFixture(overrides: Partial<StandupFormPayload> = {}): StandupFormPayload {
  return formFixture({
    mode: "edit",
    standup: standupFixture(),
    template_key: null,
    show_platform_picker: false,
    platform_locked: true,
    channel: { input: "prefixed_text", prefix: "#", value: "eng-standup", name: null, choices: [], placeholder: "eng-standup", hint: null },
    question_rows: ["What did you do yesterday?", "What will you do today?", ""],
    participant_rows: [
      {
        id: 1,
        platform_user_id: "U1",
        original_platform_user_id: "U1",
        display_name: "Ada Lovelace",
        cached_timezone: "Europe/London",
        avatar_url: null,
        active: true,
        destroy: false,
        label: "Ada Lovelace",
        pending: false,
        meta: null,
      },
      {
        id: 2,
        platform_user_id: "U2",
        original_platform_user_id: "U2",
        display_name: "Grace Hopper",
        cached_timezone: null,
        avatar_url: null,
        active: false,
        destroy: false,
        label: "Grace Hopper",
        pending: false,
        meta: "inactive",
      },
    ],
    participants_hint: "Names and timezones come from Slack.",
    default_preview_timezone: null,
    preview_timezone: "UTC",
    ...overrides,
  });
}
