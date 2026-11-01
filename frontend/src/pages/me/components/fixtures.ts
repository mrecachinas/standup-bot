import type { MemberAvailabilityPayload, MemberProfile, MemberResponsesPayload, MemberStandupsPayload, MemberStandupSummary } from "../../../api/types/member";

export const memberProfile: MemberProfile = {
  platform: "slack",
  platform_label: "Slack",
  platform_user_id: "U123",
  name: "Sam Member",
  avatar_url: null,
};

export function standupSummary(overrides: Partial<MemberStandupSummary> = {}): MemberStandupSummary {
  return {
    standup: {
      id: 7,
      name: "Daily standup",
      active: true,
      platform: "slack",
      platform_label: "Slack",
      platform_channel: "eng-standup",
      platform_channel_name: null,
      channel_reference: "#eng-standup",
      schedule_summary: "Weekdays at 9:00 AM",
    },
    participant: { id: 70, active: true, vacation_until: null },
    status_label: "Active",
    status_tone: "success",
    away: false,
    next_check_in: "2026-11-02T09:00:00-05:00",
    next_check_in_label: "Mon, Nov 2 at 9:00 AM EST",
    today: { id: 900, status: "completed", status_label: "Answered", status_tone: "success" },
    completion_rate: 80,
    completion_rate_tone: "success",
    stats: { expected: 10, completed: 8, missed: 2 },
    teammates: [
      { name: "Alex Kim", avatar_url: null },
      { name: "Bea Lopez", avatar_url: null },
    ],
    ...overrides,
  };
}

export function standupsPayload(overrides: Partial<MemberStandupsPayload> = {}): MemberStandupsPayload {
  return {
    member: memberProfile,
    away_until: null,
    away_until_label: null,
    stats: {
      standups_count: 2,
      active_count: 1,
      period_days: 30,
      expected: 10,
      completed: 8,
      completion_rate: 80,
      next_check_in: {
        at: "2026-11-02T09:00:00-05:00",
        standup_id: 7,
        standup_name: "Daily standup",
        date_label: "Mon, Nov 2",
        time_label: "9:00 AM EST",
      },
      status_label: "Available",
      status_detail: "Getting check-ins as scheduled",
    },
    standups: [
      standupSummary(),
      standupSummary({
        standup: {
          id: 8,
          name: "Retro",
          active: false,
          platform: "slack",
          platform_label: "Slack",
          platform_channel: "retro",
          platform_channel_name: null,
          channel_reference: "#retro",
          schedule_summary: "Fridays at 3:00 PM",
        },
        participant: { id: 80, active: true, vacation_until: null },
        status_label: "Standup paused",
        status_tone: "warning",
        next_check_in: null,
        next_check_in_label: null,
        today: null,
        completion_rate: null,
        completion_rate_tone: null,
        stats: null,
        teammates: [],
      }),
    ],
    ...overrides,
  };
}

export function responsesPayload(overrides: Partial<MemberResponsesPayload> = {}): MemberResponsesPayload {
  return {
    member: memberProfile,
    standups: [
      { id: 7, name: "Daily standup" },
      { id: 8, name: "Retro" },
    ],
    standup: null,
    responses: [
      {
        id: 501,
        standup_id: 7,
        standup_name: "Daily standup",
        date: "2026-10-30",
        date_label: "Friday, October 30, 2026",
        status: "completed",
        status_label: "Answered",
        status_tone: "success",
        answers: [
          { question: "What did you do yesterday?", answer: "Shipped the console" },
          { question: "Any blockers?", answer: null },
        ],
        created_at: "2026-10-30T09:00:00-05:00",
        updated_at: "2026-10-30T09:05:00-05:00",
      },
      {
        id: 502,
        standup_id: 8,
        standup_name: "Retro",
        date: "2026-10-31",
        date_label: "Saturday, October 31, 2026",
        status: "pending",
        status_label: "Pending",
        status_tone: "info",
        answers: [],
        created_at: "2026-10-31T09:00:00-05:00",
        updated_at: "2026-10-31T09:00:00-05:00",
      },
      {
        id: 503,
        standup_id: 8,
        standup_name: "Retro",
        date: "2026-10-24",
        date_label: "Saturday, October 24, 2026",
        status: "missed",
        status_label: "Missed",
        status_tone: "warning",
        answers: [],
        created_at: "2026-10-24T09:00:00-05:00",
        updated_at: "2026-10-24T09:00:00-05:00",
      },
    ],
    limit: 30,
    limited: false,
    ...overrides,
  };
}

export function availabilityPayload(overrides: Partial<MemberAvailabilityPayload> = {}): MemberAvailabilityPayload {
  return {
    member: memberProfile,
    today: "2026-11-01",
    min_date: "2026-11-01",
    max_date: "2027-11-01",
    max_away_days: 365,
    away: [],
    standups: [
      { participant_id: 70, standup_id: 7, standup_name: "Daily standup", selected: true },
      { participant_id: 80, standup_id: 8, standup_name: "Retro", selected: true },
    ],
    ...overrides,
  };
}
