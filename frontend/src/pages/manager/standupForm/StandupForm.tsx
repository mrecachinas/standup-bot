import { useEffect, useId, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link as RouterLink, useBlocker, useNavigate } from "react-router";
import {
  Button,
  Checkbox,
  CheckboxGroup,
  ConfirmationDialog,
  FormControl,
  Label,
  Radio,
  RadioGroup,
  SegmentedControl,
  Select,
  TextInput,
  Textarea,
  VisuallyHidden,
} from "@primer/react";
import { CommentDiscussionIcon, HashIcon, PeopleIcon } from "@primer/octicons-react";
import { ApiError, patch, post } from "../../../api/client";
import type { PlatformKey } from "../../../api/types";
import type { Frequency, StandupFormParams, StandupFormPayload, StandupMutationResult } from "../../../api/types/standups";
import { ErrorBanner, Panel } from "../../../components";
import { fieldMessage } from "../../../lib/fieldErrors";
import { pluralize } from "../../../lib/format";
import { useMutation } from "../../../hooks/useMutation";
import { paths } from "../../../paths";
import { FieldError } from "./FieldError";
import { formatClock, formParams, initialFormState, scheduleParams, scheduleSentence, type FormState } from "./formState";
import { PeoplePicker } from "./PeoplePicker";
import { QuestionEditor } from "./QuestionEditor";
import { SchedulePreviewCard } from "./SchedulePreviewCard";
import { useSchedulePreview } from "./useSchedulePreview";
import layout from "../../../styles/layout.module.css";
import styles from "./StandupForm.module.css";

export interface StandupFormProps {
  payload: StandupFormPayload;
  /** New standups only: switch the chat platform (reloads the form). */
  onPlatformChange?: (platform: PlatformKey) => void;
  /** Extra panels under the previews, e.g. Settings' test message. */
  aside?: ReactNode;
}

const ADVANCED_FIELDS = ["schedule_type", "respect_timezone", "reminder_enabled", "reminder_after_minutes", "max_reminders", "intro", "outro"];

/** The standup editor (create and settings): basics, schedule, questions, people, advanced, and live previews. */
export function StandupForm({ payload, onPlatformChange, aside }: StandupFormProps) {
  const navigate = useNavigate();
  const ids = useIds();
  const [state, setState] = useState<FormState>(() => initialFormState(payload));
  const [handleText, setHandleText] = useState("");
  const [advancedOpen, setAdvancedOpen] = useState(payload.advanced_open);
  const [dirty, setDirty] = useState(false);
  const dirtyRef = useRef(false);
  const errorRef = useRef<HTMLDivElement>(null);
  const isNew = payload.mode === "new";
  const standupId = payload.standup.id;
  const platform = payload.platform;

  const preview = useSchedulePreview(payload, scheduleParams(state));

  const update = (changes: Partial<FormState>) => {
    setState((current) => ({ ...current, ...changes }));
    markDirty();
  };

  const markDirty = () => {
    dirtyRef.current = true;
    setDirty(true);
  };

  const save = useMutation(
    (params: StandupFormParams) =>
      (isNew
        ? post<StandupMutationResult>("/api/standups", { standup: params })
        : patch<StandupMutationResult>(`/api/standups/${standupId}`, { standup: params })
      ).catch((error: unknown) => {
        if (error instanceof ApiError && hasAdvancedErrors(error.fieldErrors)) setAdvancedOpen(true);
        throw error;
      }),
    {
      refreshSidebar: true,
      onSuccess: (result) => {
        dirtyRef.current = false;
        navigate(paths.standup(result.standup.id));
      },
    },
  );

  // Leaving with unsaved changes asks first, in the app and when closing the tab.
  const blocker = useBlocker(
    ({ currentLocation, nextLocation }) =>
      dirtyRef.current && (currentLocation.pathname !== nextLocation.pathname || currentLocation.search !== nextLocation.search),
  );
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => {
      if (!dirtyRef.current) return;
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  useEffect(() => {
    if (save.error) errorRef.current?.scrollIntoView({ block: "start" });
  }, [save.error]);

  useEffect(() => {
    const hash = window.location.hash.slice(1);
    if (hash) document.getElementById(hash)?.scrollIntoView({ block: "start" });
  }, []);

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    await save.run(formParams(state, payload, handleText));
  };

  const fieldError = (label: string, ...keys: string[]) => fieldMessage(save.error, keys, label);

  const fieldErrors = save.error?.fieldErrors ?? {};
  const errorCount = save.error ? save.error.errors.length : 0;
  const frequencyHint = payload.frequency_options.find((option) => option.value === state.frequency)?.hint;
  const firstQuestion = state.questions.map((row) => row.text.trim()).filter(Boolean);
  const nameError = fieldError("Name", "name");
  const channelError = fieldError("Channel", "platform_channel", "platform_channel_name");
  const daysError = fieldError("Days", "schedule_days", "schedule_type");
  const timeError = fieldError("Time", "default_hour", "default_minute");
  const remindersError = fieldError("Reminders", "reminder_after_minutes", "max_reminders", "reminder_enabled");
  const questionsError = fieldError("Questions", "questions");
  const timezoneError = fieldError("Timezone", "respect_timezone");
  const introError = fieldError("Greeting", "intro");
  const outroError = fieldError("Sign-off", "outro");

  return (
    <form className={styles.editor} onSubmit={handleSubmit} noValidate aria-label={isNew ? "New standup" : "Standup settings"}>
      <div ref={errorRef} className={styles.errors}>
        <ErrorBanner error={save.error} title={`${pluralize(errorCount, "error")} prevented saving`} onDismiss={save.reset} />
      </div>

      <div className={styles.layout}>
        <div className={styles.main}>
          <Panel
            id="basics"
            title={payload.show_platform_picker ? "Chat platform" : undefined}
            description={payload.show_platform_picker ? "Where people get their questions. This can't be changed later." : undefined}
            actions={
              payload.show_platform_picker ? (
                <SegmentedControl
                  aria-label="Chat platform"
                  size="small"
                  onChange={(index) => {
                    const option = payload.platform_options[index];
                    if (option && option.key !== platform.key) onPlatformChange?.(option.key);
                  }}
                >
                  {payload.platform_options.map((option) => (
                    <SegmentedControl.Button
                      key={option.key}
                      selected={option.key === platform.key}
                      leadingVisual={option.icon === "people" ? PeopleIcon : HashIcon}
                    >
                      {option.label}
                    </SegmentedControl.Button>
                  ))}
                </SegmentedControl>
              ) : undefined
            }
          >
            <FieldError id={ids.platform} message={fieldError("Platform", "platform")} />
            <div className={styles.grid2}>
              <FormControl required>
                <FormControl.Label>Name</FormControl.Label>
                <TextInput
                  block
                  value={state.name}
                  placeholder="Platform daily"
                  autoFocus={isNew}
                  validationStatus={nameError ? "error" : undefined}
                  onChange={(event) => update({ name: event.target.value })}
                />
                {nameError && <FormControl.Validation variant="error">{nameError}</FormControl.Validation>}
              </FormControl>
              <ChannelField payload={payload} state={state} error={channelError} onChange={update} />
            </div>
          </Panel>

          <Panel id="schedule" title="When" description={<span aria-live="polite">{scheduleSentence(state)}</span>}>
            <div className={styles.scheduleRow}>
              {state.frequency !== "monthly" ? (
                <div className={styles.dayPicker}>
                  <CheckboxGroup aria-describedby={daysError ? ids.days : undefined}>
                    <CheckboxGroup.Label>Days</CheckboxGroup.Label>
                    <div className={styles.dayPills}>
                      {payload.weekday_options.map((day) => (
                        <label key={day.value} className={styles.dayPill}>
                          <input
                            type="checkbox"
                            className={styles.dayPillInput}
                            value={String(day.value)}
                            checked={state.days.includes(day.value)}
                            onChange={(event) =>
                              update({
                                days: event.target.checked
                                  ? [...state.days, day.value].sort((a, b) => a - b)
                                  : state.days.filter((value) => value !== day.value),
                              })
                            }
                          />
                          <span aria-hidden="true">{day.short_label}</span>
                          <VisuallyHidden>{day.label}</VisuallyHidden>
                        </label>
                      ))}
                    </div>
                  </CheckboxGroup>
                  <div className={styles.presets}>
                    {payload.day_presets.map((preset) => (
                      <Button key={preset.label} type="button" size="small" variant="link" onClick={() => update({ days: [...preset.days] })}>
                        {preset.label}
                      </Button>
                    ))}
                  </div>
                  <FieldError id={ids.days} message={daysError} />
                </div>
              ) : (
                <FormControl>
                  <FormControl.Label>Day of the month</FormControl.Label>
                  <TextInput
                    type="number"
                    min={1}
                    max={31}
                    value={state.monthlyDay}
                    validationStatus={daysError ? "error" : undefined}
                    onChange={(event) => update({ monthlyDay: event.target.value })}
                  />
                  {daysError && <FormControl.Validation variant="error">{daysError}</FormControl.Validation>}
                </FormControl>
              )}
              <FormControl required>
                <FormControl.Label>At</FormControl.Label>
                <TextInput
                  type="time"
                  value={state.sendTime}
                  validationStatus={timeError ? "error" : undefined}
                  onChange={(event) => update({ sendTime: event.target.value })}
                />
                {timeError && <FormControl.Validation variant="error">{timeError}</FormControl.Validation>}
              </FormControl>
            </div>
          </Panel>

          <Panel id="questions" title="Questions" description={payload.message_preview.hint}>
            <QuestionEditor
              questions={state.questions}
              onChange={(questions) => update({ questions })}
              suggestions={payload.question_suggestions.map((suggestion) => suggestion.text)}
              describedBy={questionsError ? ids.questions : undefined}
              invalid={Boolean(questionsError)}
            />
            <FieldError id={ids.questions} message={questionsError} />
          </Panel>

          {/* Once a standup exists, people are managed on its People tab. */}
          {isNew && (
            <Panel id="participants" title="People" description={payload.participants_hint}>
              <PeoplePicker
                platform={platform.key}
                people={state.people}
                onChange={(people) => update({ people })}
                query={handleText}
                onQueryChange={(text) => {
                  setHandleText(text);
                  if (text) markDirty();
                }}
                placeholder={`Add people: ${platform.copy.user_placeholder ?? platform.user_id_hint}, then press Enter`}
              />
            </Panel>
          )}

          <details
            id="advanced"
            className={styles.disclosure}
            open={advancedOpen}
            onToggle={(event) => setAdvancedOpen(event.currentTarget.open)}
          >
            <summary>
              <span className={styles.summaryTitle}>Advanced settings</span>
              <span className={layout.hint}>Repeat interval, timezone, reminders, and messages</span>
            </summary>
            <div className={styles.disclosureBody}>
              <RadioGroup
                name={ids.frequency}
                onChange={(value) => value && update({ frequency: value as Frequency })}
                aria-describedby={frequencyHint ? ids.frequencyHint : undefined}
              >
                <RadioGroup.Label>Repeat</RadioGroup.Label>
                <div className={styles.inlineChoices}>
                  {payload.frequency_options.map((option) => (
                    <FormControl key={option.value}>
                      <Radio value={option.value} checked={state.frequency === option.value} />
                      <FormControl.Label>{option.label}</FormControl.Label>
                    </FormControl>
                  ))}
                </div>
              </RadioGroup>
              {frequencyHint && (
                <p id={ids.frequencyHint} className={layout.hint}>
                  {frequencyHint}
                </p>
              )}

              <FormControl className={styles.narrowField}>
                <FormControl.Label>Send at</FormControl.Label>
                <Select value={String(state.respectTimezone)} onChange={(event) => update({ respectTimezone: event.target.value === "true" })}>
                  {payload.respect_timezone_options.map((option) => (
                    <Select.Option key={String(option.value)} value={String(option.value)}>
                      {option.label}
                    </Select.Option>
                  ))}
                </Select>
                {timezoneError && <FormControl.Validation variant="error">{timezoneError}</FormControl.Validation>}
              </FormControl>

              <fieldset className={styles.fieldset} aria-describedby={remindersError ? ids.reminders : undefined}>
                <legend className={styles.legend}>Reminders</legend>
                <div className={styles.inlineFields}>
                  <FormControl>
                    <Checkbox checked={state.reminderEnabled} onChange={(event) => update({ reminderEnabled: event.target.checked })} />
                    <FormControl.Label>Remind people who haven't answered after</FormControl.Label>
                  </FormControl>
                  <TextInput
                    type="number"
                    min={1}
                    step={1}
                    className={styles.numberInput}
                    aria-label="Minutes before the first reminder"
                    value={state.reminderAfterMinutes}
                    validationStatus={fieldErrors.reminder_after_minutes ? "error" : undefined}
                    onChange={(event) => update({ reminderAfterMinutes: event.target.value })}
                  />
                  <span>minutes, up to</span>
                  <TextInput
                    type="number"
                    min={0}
                    step={1}
                    className={styles.numberInput}
                    aria-label="Maximum reminders"
                    value={state.maxReminders}
                    validationStatus={fieldErrors.max_reminders ? "error" : undefined}
                    onChange={(event) => update({ maxReminders: event.target.value })}
                  />
                  <span>times</span>
                </div>
                <FieldError id={ids.reminders} message={remindersError} />
              </fieldset>

              <div className={styles.grid2}>
                <FormControl>
                  <FormControl.Label>Greeting</FormControl.Label>
                  <Textarea
                    block
                    rows={3}
                    value={state.intro}
                    placeholder="Morning! Time for a quick standup."
                    onChange={(event) => update({ intro: event.target.value })}
                  />
                  {introError && <FormControl.Validation variant="error">{introError}</FormControl.Validation>}
                </FormControl>
                <FormControl>
                  <FormControl.Label>Sign-off</FormControl.Label>
                  <Textarea
                    block
                    rows={3}
                    value={state.outro}
                    placeholder="Thanks, have a good day."
                    onChange={(event) => update({ outro: event.target.value })}
                  />
                  {outroError && <FormControl.Validation variant="error">{outroError}</FormControl.Validation>}
                </FormControl>
              </div>
            </div>
          </details>

          <div className={styles.actions}>
            <Button as={RouterLink} to={standupId === null ? paths.standups : paths.standup(standupId)} variant="invisible">
              Cancel
            </Button>
            <Button type="submit" variant="primary" loading={save.loading}>
              {isNew ? "Create standup" : "Save changes"}
            </Button>
          </div>
        </div>

        <aside className={styles.aside} aria-label="Previews">
          <Panel title="What people see">
            <MessagePreview
              platformLabel={platform.label}
              time={formatClock(state.sendTime)}
              intro={state.intro.trim()}
              questionCount={Math.max(firstQuestion.length, 1)}
              firstQuestion={firstQuestion[0] ?? "Your first question shows up here."}
            />
          </Panel>
          <SchedulePreviewCard
            options={payload.time_zone_options}
            preview={preview.preview}
            error={preview.error}
            loading={preview.loading}
            timezone={preview.timezone}
            onTimezoneChange={preview.setTimezone}
            onRefresh={preview.refresh}
          />
          {aside}
        </aside>
      </div>

      {blocker.state === "blocked" && (
        <ConfirmationDialog
          title="Leave without saving?"
          onClose={(gesture) => (gesture === "confirm" ? blocker.proceed() : blocker.reset())}
          confirmButtonContent="Leave"
          cancelButtonContent="Stay"
          confirmButtonType="danger"
        >
          You have unsaved changes. Leave anyway?
        </ConfirmationDialog>
      )}
    </form>
  );
}

function ChannelField({
  payload,
  state,
  error,
  onChange,
}: {
  payload: StandupFormPayload;
  state: FormState;
  error: string | undefined;
  onChange: (changes: Partial<FormState>) => void;
}) {
  const { channel } = payload;

  return (
    <FormControl required>
      <FormControl.Label>Post summaries to</FormControl.Label>
      {channel.input === "select" ? (
        <Select
          block
          value={state.platformChannel}
          validationStatus={error ? "error" : undefined}
          onChange={(event) => {
            const choice = channel.choices.find((option) => option.id === event.target.value);
            onChange({ platformChannel: event.target.value, platformChannelName: choice?.label ?? "" });
          }}
        >
          <Select.Option value="">{channel.placeholder}</Select.Option>
          {channel.choices.map((choice) => (
            <Select.Option key={choice.id} value={choice.id}>
              {choice.label}
            </Select.Option>
          ))}
        </Select>
      ) : (
        <TextInput
          block
          value={state.platformChannel}
          placeholder={channel.placeholder}
          leadingVisual={channel.input === "prefixed_text" ? (channel.prefix ?? "#") : undefined}
          validationStatus={error ? "error" : undefined}
          onChange={(event) =>
            onChange({ platformChannel: channel.input === "prefixed_text" ? event.target.value.replace(/^#/, "") : event.target.value })
          }
        />
      )}
      {channel.hint && <FormControl.Caption>{channel.hint}</FormControl.Caption>}
      {error && <FormControl.Validation variant="error">{error}</FormControl.Validation>}
    </FormControl>
  );
}

function MessagePreview({
  platformLabel,
  time,
  intro,
  questionCount,
  firstQuestion,
}: {
  platformLabel: string;
  time: string;
  intro: string;
  questionCount: number;
  firstQuestion: string;
}) {
  return (
    <div className={styles.dmPreview} role="group" aria-label={`Preview of the ${platformLabel} DM`}>
      <span className={styles.dmIcon} aria-hidden="true">
        <CommentDiscussionIcon size={20} />
      </span>
      <div className={layout.grow}>
        <div className={styles.dmMeta}>
          <strong>Standup Bot</strong>
          <Label size="small">APP</Label>
          <span className={layout.hint}>{time}</span>
        </div>
        {intro && <p className={styles.dmText}>{intro}</p>}
        <p className={styles.dmQuestion}>
          <span className={layout.hint}>Question 1 of {questionCount}</span>
          <span>{firstQuestion}</span>
        </p>
      </div>
    </div>
  );
}

function useIds() {
  const base = useId();
  return {
    platform: `${base}-platform`,
    days: `${base}-days`,
    questions: `${base}-questions`,
    reminders: `${base}-reminders`,
    frequency: `${base}-frequency`,
    frequencyHint: `${base}-frequency-hint`,
  };
}

function hasAdvancedErrors(fieldErrors: Record<string, string[]> | undefined): boolean {
  return Boolean(fieldErrors && ADVANCED_FIELDS.some((key) => (fieldErrors[key] ?? []).length > 0));
}
