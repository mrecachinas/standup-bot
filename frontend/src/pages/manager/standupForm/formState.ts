import type { Frequency, ParticipantRow, PersonResult, StandupFormParams, StandupFormPayload } from "../../../api/types/standups";

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WEEKDAYS = "1,2,3,4,5";

let nextKey = 0;
/** A stable React key for rows the editor adds. */
export function newKey(prefix: string): string {
  nextKey += 1;
  return `${prefix}-${nextKey}`;
}

export interface QuestionRow {
  key: string;
  text: string;
}

export interface PersonChip {
  key: string;
  id: number | null;
  platform_user_id: string;
  original_platform_user_id: string;
  display_name: string;
  cached_timezone: string;
  avatar_url: string | null;
  active: boolean;
  /** Marked for removal on save (people the server sent can be restored). */
  destroy: boolean;
  /** Typed as a handle; the server looks the person up on save. */
  pending: boolean;
  /** Came with the form payload, so removing it only marks it (restorable). */
  fromServer: boolean;
}

export interface FormState {
  name: string;
  platformChannel: string;
  platformChannelName: string;
  intro: string;
  outro: string;
  reminderEnabled: boolean;
  reminderAfterMinutes: string;
  maxReminders: string;
  respectTimezone: boolean;
  sendTime: string;
  frequency: Frequency;
  days: number[];
  monthlyDay: string;
  questions: QuestionRow[];
  people: PersonChip[];
}

export function initialFormState(payload: StandupFormPayload): FormState {
  const { standup, channel } = payload;
  const picker = standup.schedule_picker ?? { frequency: "weekly", days: [] };
  const selectedChoice = channel.input === "select" ? channel.choices.find((choice) => choice.id === channel.value) : undefined;

  return {
    name: standup.name ?? "",
    platformChannel: channel.value ?? "",
    platformChannelName: selectedChoice?.label ?? channel.name ?? "",
    intro: standup.intro ?? "",
    outro: standup.outro ?? "",
    reminderEnabled: Boolean(standup.reminder_enabled),
    reminderAfterMinutes: numberText(standup.reminder_after_minutes),
    maxReminders: numberText(standup.max_reminders),
    respectTimezone: standup.respect_timezone,
    sendTime: payload.send_time,
    frequency: (["weekly", "biweekly", "monthly"].includes(picker.frequency) ? picker.frequency : "weekly") as Frequency,
    days: [...picker.days].map(Number).sort((a, b) => a - b),
    monthlyDay: String(payload.monthly_day ?? 1),
    questions: (payload.question_rows.length > 0 ? payload.question_rows : [""]).map((text) => ({ key: newKey("question"), text })),
    people: payload.participant_rows.map(chipFromRow),
  };
}

function numberText(value: number | null | undefined): string {
  return value === null || value === undefined ? "" : String(value);
}

function chipFromRow(row: ParticipantRow): PersonChip {
  return {
    key: newKey("person"),
    id: row.id,
    platform_user_id: row.platform_user_id ?? "",
    original_platform_user_id: row.original_platform_user_id ?? row.platform_user_id ?? "",
    display_name: row.display_name ?? "",
    cached_timezone: row.cached_timezone ?? "",
    avatar_url: row.avatar_url,
    active: row.active,
    destroy: row.destroy,
    pending: row.pending,
    fromServer: true,
  };
}

export function chipFromPerson(person: PersonResult): PersonChip {
  return {
    key: newKey("person"),
    id: null,
    platform_user_id: person.platform_user_id,
    original_platform_user_id: "",
    display_name: person.display_name,
    cached_timezone: person.timezone ?? "",
    avatar_url: person.avatar_url,
    active: true,
    destroy: false,
    pending: false,
    fromServer: false,
  };
}

export function chipFromHandle(handle: string): PersonChip {
  return {
    key: newKey("person"),
    id: null,
    platform_user_id: handle,
    original_platform_user_id: "",
    display_name: "",
    cached_timezone: "",
    avatar_url: null,
    active: true,
    destroy: false,
    pending: true,
    fromServer: false,
  };
}

/** "Ada", or the handle while it's waiting to be looked up. */
export function chipLabel(chip: PersonChip): string {
  return chip.display_name || chip.platform_user_id;
}

/** Splits "@ada, Grace Hopper\nU123" into handles. */
export function splitHandles(text: string): string[] {
  return text
    .split(/[,\n]/)
    .map((handle) => handle.trim())
    .filter(Boolean);
}

/** Adds chips for people not already on the list (by ID, case-insensitively). */
export function addChips(people: PersonChip[], chips: PersonChip[]): PersonChip[] {
  const existing = new Set(people.map((chip) => chip.platform_user_id.toLowerCase()));
  const added: PersonChip[] = [];
  for (const chip of chips) {
    const id = chip.platform_user_id.toLowerCase();
    if (!id || existing.has(id)) continue;
    existing.add(id);
    added.push(chip);
  }
  return added.length > 0 ? [...people, ...added] : people;
}

/** "9:30 AM" from "09:30". */
export function formatClock(value: string): string {
  const [hours, minutes] = (value || "").split(":").map((part) => (part === "" ? Number.NaN : Number(part)));
  if (hours === undefined || minutes === undefined || Number.isNaN(hours) || Number.isNaN(minutes)) return "—";
  const suffix = hours >= 12 ? "PM" : "AM";
  return `${hours % 12 || 12}:${String(minutes).padStart(2, "0")} ${suffix}`;
}

/** The "When" section's live summary, e.g. "Weekdays at 9:30 AM, in each person's local time". */
export function scheduleSentence(state: Pick<FormState, "frequency" | "days" | "monthlyDay" | "sendTime" | "respectTimezone">): string {
  const days = [...state.days].sort((a, b) => a - b);
  const names = days.map((day) => DAY_NAMES[day]);
  let base: string;

  if (state.frequency === "monthly") {
    base = `Monthly on day ${state.monthlyDay || 1}`;
  } else if (state.frequency === "biweekly") {
    base = days.length === 1 ? `Every 2 weeks on ${names[0]}` : "Every 2 weeks (pick one day)";
  } else if (days.length === 0) {
    return "Pick at least one day.";
  } else if (days.length === 7) {
    base = "Every day";
  } else if (days.join() === WEEKDAYS) {
    base = "Weekdays";
  } else if (days.length === 1) {
    base = `Weekly on ${names[0]}`;
  } else {
    base = names.join(", ");
  }

  return `${base} at ${formatClock(state.sendTime)}, ${state.respectTimezone ? "in each person's local time" : "UTC"}`;
}

/** The schedule fields POST /api/standups/preview needs. */
export function scheduleParams(state: FormState) {
  return {
    frequency: state.frequency,
    ...(state.frequency === "monthly" ? { days: [] as number[], monthly_day: state.monthlyDay } : { days: [...state.days].sort((a, b) => a - b) }),
    send_time: state.sendTime,
    respect_timezone: state.respectTimezone,
  };
}

/** The `standup` params for POST /api/standups and PATCH /api/standups/:id. */
export function formParams(state: FormState, payload: StandupFormPayload, handleText: string): StandupFormParams {
  const schedule = scheduleParams(state);
  return {
    name: state.name.trim(),
    ...(payload.mode === "new" ? { platform: payload.platform.key } : {}),
    platform_channel: state.platformChannel.trim(),
    // Pickers know a channel's name; plain typed channels leave it alone. A
    // Slack name typed instead of picked clears the old one.
    ...(payload.channel.input === "select" ? { platform_channel_name: state.platformChannelName } : {}),
    ...(payload.channel.input === "search" ? { platform_channel_name: state.platformChannelName.trim() || null } : {}),
    intro: state.intro,
    outro: state.outro,
    reminder_enabled: state.reminderEnabled,
    reminder_after_minutes: state.reminderAfterMinutes,
    max_reminders: state.maxReminders,
    respect_timezone: state.respectTimezone,
    send_time: state.sendTime,
    frequency: schedule.frequency,
    days: schedule.days,
    monthly_day: state.monthlyDay,
    question_rows: state.questions.map((row) => row.text),
    // Editing leaves people alone: the People tab manages them.
    ...(payload.mode === "new" ? newParticipantParams(state, handleText) : {}),
  };
}

function newParticipantParams(state: FormState, handleText: string): Pick<StandupFormParams, "participants" | "participant_handles"> {
  return {
    participants: state.people
      .filter((chip) => chip.fromServer || !chip.destroy)
      .map((chip) => ({
        id: chip.id,
        platform_user_id: chip.platform_user_id,
        original_platform_user_id: chip.original_platform_user_id,
        display_name: chip.display_name,
        cached_timezone: chip.cached_timezone,
        active: chip.active,
        _destroy: chip.destroy,
      })),
    participant_handles: handleText.trim(),
  };
}
