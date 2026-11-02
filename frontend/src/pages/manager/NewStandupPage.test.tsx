import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { jsonResponse, teamsPlatform, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { formFixture, occurrence, standupFixture, standupOverviewFixture } from "./standups/testFixtures";

type FetchMock = ReturnType<typeof mockFetch>;

function bodiesFor(fetchMock: FetchMock, url: string, method = "POST") {
  return fetchMock.mock.calls
    .filter(([requestUrl, init]) => String(requestUrl) === url && init?.method === method)
    .map(([, init]) => JSON.parse(String(init!.body)));
}

function urls(fetchMock: FetchMock) {
  return fetchMock.mock.calls.map(([url]) => String(url));
}

function setup(handler?: Parameters<typeof mockFetch>[1], payload = formFixture()) {
  return mockFetch(userBootstrap(), async (url, init) => {
    const handled = await handler?.(url, init);
    if (handled) return handled;
    if (url.startsWith("/api/standups/new")) return jsonResponse(payload);
    if (url === "/api/standups/preview") return jsonResponse(payload.schedule_preview);
    return undefined;
  });
}

describe("NewStandupPage", () => {
  it("shows the templates, platform picker, editor and previews", async () => {
    const fetchMock = setup();
    renderApp("/manager/standups/new");

    expect(await screen.findByLabelText(/^Name/)).toHaveValue("");
    await waitFor(() => expect(document.title).toBe("New standup · Standup Bot"));
    expect(urls(fetchMock)).toContain("/api/standups/new");
    expect(screen.getByRole("heading", { name: "Create a standup", level: 1 })).toBeInTheDocument();

    const templates = screen.getByRole("navigation", { name: "Templates" });
    expect(within(templates).getByRole("link", { name: /Daily standup/ })).toHaveAttribute("aria-current", "true");
    expect(within(templates).getByRole("link", { name: /Friday retro/ })).toHaveAttribute("href", "/manager/standups/new?template=retro&platform=slack");
    expect(screen.getByText("Fridays at 3:00 PM · 3 questions")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "start from scratch" })).toHaveAttribute("href", "/manager/standups/new?template=blank&platform=slack");

    expect(screen.getByRole("button", { name: "Slack" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByLabelText(/Post summaries to/)).toHaveAttribute("placeholder", "eng-standup");
    expect(screen.getByText("Weekdays at 9:30 AM, in each person's local time")).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "Monday" })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: "Sunday" })).not.toBeChecked();
    expect(screen.getByLabelText(/^At/)).toHaveValue("09:30");
    expect(screen.getByRole("textbox", { name: "Question 1" })).toHaveValue("What did you get done yesterday?");
    expect(screen.getAllByRole("textbox", { name: /^Question \d$/ })).toHaveLength(4);
    expect(screen.getByRole("button", { name: "Where could you use help?" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "What did you get done yesterday?" })).toBeNull();
    expect(within(screen.getByRole("list", { name: "People in this standup" })).getByText("Maya Manager")).toBeInTheDocument();

    const dm = screen.getByRole("group", { name: "Preview of the Slack DM" });
    expect(within(dm).getByText("Question 1 of 3")).toBeInTheDocument();
    expect(within(dm).getByText("What did you get done yesterday?")).toBeInTheDocument();
    expect(within(dm).getByText("9:30 AM")).toBeInTheDocument();
    expect(screen.getByLabelText("Preview timezone")).toHaveValue("Eastern Time (US & Canada)");
    expect(within(screen.getByRole("list", { name: "Next runs" })).getByText("Monday")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create standup" })).toBeInTheDocument();
  });

  it("loads a template and switches platform through the URL", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url) => {
      if (url === "/api/standups/new?template=retro&platform=slack") return jsonResponse(formFixture({ template_key: "retro", question_rows: ["What went well this week?", ""] }));
      if (url === "/api/standups/new?template=retro&platform=teams") {
        return jsonResponse(
          formFixture({
            template_key: "retro",
            platform: teamsPlatform,
            channel: { input: "text", value: "", name: null, choices: [], placeholder: "TEAM_ID|19:…@thread.tacv2", hint: "Set up Teams on the Integrations page to pick a channel from a list." },
          }),
        );
      }
      return undefined;
    });
    const { router } = renderApp("/manager/standups/new");

    await user.click(await screen.findByRole("link", { name: /Friday retro/ }));
    expect(await screen.findByDisplayValue("What went well this week?")).toBeInTheDocument();
    expect(router.state.location.search).toBe("?template=retro&platform=slack");

    await user.click(screen.getByRole("button", { name: "Microsoft Teams" }));
    expect(await screen.findByText("Set up Teams on the Integrations page to pick a channel from a list.")).toBeInTheDocument();
    expect(urls(fetchMock)).toContain("/api/standups/new?template=retro&platform=teams");
    expect(screen.getByLabelText(/Post summaries to/)).toHaveAttribute("placeholder", "TEAM_ID|19:…@thread.tacv2");
  });

  it("creates the standup and opens it", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) => {
      if (url === "/api/standups" && init.method === "POST") return jsonResponse({ standup: standupFixture({ id: 42, name: "Platform daily" }), notice: "Platform daily was created." }, 201);
      if (url === "/api/standups/42?include=overview") return jsonResponse(standupOverviewFixture({}, { id: 42, name: "Platform daily" }));
      return undefined;
    });
    const { router } = renderApp("/manager/standups/new");

    await user.type(await screen.findByLabelText(/^Name/), "Platform daily");
    await user.type(screen.getByLabelText(/Post summaries to/), "#platform");
    await user.click(screen.getByRole("button", { name: "Create standup" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/standups/42"));
    expect(await screen.findByText("Platform daily was created.")).toBeInTheDocument();
    const [body] = bodiesFor(fetchMock, "/api/standups");
    expect(body).toEqual({
      standup: {
        name: "Platform daily",
        platform: "slack",
        platform_channel: "platform",
        intro: "",
        outro: "",
        reminder_enabled: true,
        reminder_after_minutes: "60",
        max_reminders: "2",
        respect_timezone: true,
        send_time: "09:30",
        frequency: "weekly",
        days: [1, 2, 3, 4, 5],
        monthly_day: "1",
        question_rows: ["What did you get done yesterday?", "What are you working on today?", "Is anything blocking you?", ""],
        participants: [
          {
            id: null,
            platform_user_id: "U0MAYA",
            original_platform_user_id: "U0MAYA",
            display_name: "Maya Manager",
            cached_timezone: "America/New_York",
            active: true,
            _destroy: false,
          },
        ],
        participant_handles: "",
      },
    });
    // Creating a standup refreshes the sidebar.
    expect(urls(fetchMock).filter((url) => url === "/api/session").length).toBeGreaterThan(1);
  });

  it("shows validation errors on their fields and in a banner", async () => {
    const user = userEvent.setup();
    setup((url, init) =>
      url === "/api/standups" && init.method === "POST"
        ? jsonResponse(
            {
              errors: ["Name can't be blank", "Questions can't be blank", "Participant 1: Couldn't find @nobody"],
              field_errors: { name: ["can't be blank"], questions: ["can't be blank"], base: ["Participant 1: Couldn't find @nobody"] },
            },
            422,
          )
        : undefined,
    );
    renderApp("/manager/standups/new");

    await user.click(await screen.findByRole("button", { name: "Create standup" }));

    expect(await screen.findByText("3 errors prevented saving")).toBeInTheDocument();
    expect(screen.getByText("Participant 1: Couldn't find @nobody")).toBeInTheDocument();
    expect(screen.getByLabelText(/^Name/)).toHaveAttribute("aria-invalid", "true");
    expect(screen.getAllByText("Name can't be blank")).toHaveLength(2);
    expect(screen.getByRole("textbox", { name: "Question 1" })).toHaveAccessibleDescription("Questions can't be blank");
  });

  it("edits questions: Enter adds a row, rows reorder and remove, suggestions fill empty rows", async () => {
    const user = userEvent.setup();
    setup(undefined, formFixture({ question_rows: ["First?", ""] }));
    renderApp("/manager/standups/new");

    const first = await screen.findByRole("textbox", { name: "Question 1" });
    await user.click(first);
    await user.keyboard("{End}{Enter}");
    expect(screen.getAllByRole("textbox", { name: /^Question \d$/ })).toHaveLength(3);
    expect(screen.getByRole("textbox", { name: "Question 2" })).toHaveFocus();
    await user.keyboard("Second?");

    await user.click(screen.getByRole("button", { name: "Move question 2 up" }));
    expect(screen.getByRole("textbox", { name: "Question 1" })).toHaveValue("Second?");
    expect(screen.getByRole("textbox", { name: "Question 2" })).toHaveValue("First?");
    expect(screen.getByRole("button", { name: "Move question 1 up" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Where could you use help?" }));
    expect(screen.getByRole("textbox", { name: "Question 3" })).toHaveValue("Where could you use help?");
    expect(screen.queryByRole("button", { name: "Where could you use help?" })).toBeNull();
    expect(within(screen.getByRole("group", { name: "Preview of the Slack DM" })).getByText("Question 1 of 3")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remove question 3" }));
    expect(screen.getAllByRole("textbox", { name: /^Question \d$/ })).toHaveLength(2);
    expect(screen.getByRole("button", { name: "Where could you use help?" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Add question" }));
    expect(screen.getByRole("textbox", { name: "Question 3" })).toHaveFocus();
    await user.keyboard("{Backspace}");
    expect(screen.getAllByRole("textbox", { name: /^Question \d$/ })).toHaveLength(2);
    expect(screen.getByRole("textbox", { name: "Question 2" })).toHaveFocus();
  });

  it("updates the schedule summary and live preview as the schedule changes", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url) =>
      url === "/api/standups/preview"
        ? jsonResponse({ occurrences: [occurrence("2026-11-04", 4, "Wednesday")], preview_timezone: "Eastern Time (US & Canada)", error: null, empty_message: "" })
        : undefined,
    );
    renderApp("/manager/standups/new");

    await user.click(await screen.findByRole("button", { name: "Mon, Wed, Fri" }));
    expect(screen.getByText("Mon, Wed, Fri at 9:30 AM, in each person's local time")).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "Tuesday" })).not.toBeChecked();

    expect(await within(screen.getByRole("list", { name: "Next runs" })).findByText("Wednesday")).toBeInTheDocument();
    expect(bodiesFor(fetchMock, "/api/standups/preview").at(-1)).toEqual({
      standup: { platform: "slack", frequency: "weekly", days: [1, 3, 5], send_time: "09:30", respect_timezone: true },
      preview_timezone: "Eastern Time (US & Canada)",
    });

    await user.click(screen.getByRole("checkbox", { name: "Monday" }));
    await user.click(screen.getByRole("checkbox", { name: "Wednesday" }));
    await user.click(screen.getByRole("checkbox", { name: "Friday" }));
    expect(screen.getByText("Pick at least one day.")).toBeInTheDocument();

    await user.click(screen.getByText("Advanced settings"));
    await user.click(screen.getByRole("radio", { name: "Once a month" }));
    expect(screen.queryByRole("checkbox", { name: "Monday" })).toBeNull();
    expect(screen.getByLabelText("Day of the month")).toHaveValue(1);
    await user.selectOptions(screen.getByLabelText("Send at"), "false");
    expect(screen.getByText("Monthly on day 1 at 9:30 AM, UTC")).toBeInTheDocument();

    await user.click(screen.getByRole("radio", { name: "Every other week" }));
    expect(screen.getByText("Every other week runs on a single day.")).toBeInTheDocument();
    expect(screen.getByText("Every 2 weeks (pick one day) at 9:30 AM, UTC")).toBeInTheDocument();

    await user.selectOptions(screen.getByLabelText("Preview timezone"), "London");
    await waitFor(() =>
      expect(bodiesFor(fetchMock, "/api/standups/preview").at(-1)).toEqual({
        standup: { platform: "slack", frequency: "biweekly", days: [], send_time: "09:30", respect_timezone: false },
        preview_timezone: "London",
      }),
    );
  });

  it("previews in the browser's timezone when the server doesn't know it", async () => {
    vi.spyOn(Intl.DateTimeFormat.prototype, "resolvedOptions").mockReturnValue({ timeZone: "Europe/London" } as Intl.ResolvedDateTimeFormatOptions);
    const fetchMock = setup(undefined, formFixture({ detect_preview_timezone: true, default_preview_timezone: null, preview_timezone: "UTC" }));
    renderApp("/manager/standups/new");

    expect(await screen.findByLabelText("Preview timezone")).toHaveValue("London");
    await waitFor(() => expect(bodiesFor(fetchMock, "/api/standups/preview").at(-1)?.preview_timezone).toBe("London"));
    expect(screen.getByRole("button", { name: "Detect my timezone" })).toBeDisabled();
  });

  it("adds people by handle or search, and removes or restores them", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) => {
      if (url.startsWith("/api/people?")) {
        return jsonResponse({
          platform: "slack",
          people: [{ platform_user_id: "U9GRACE", display_name: "Grace Hopper", avatar_url: null, timezone: "America/New_York" }],
          success: true,
          message: "Found 1 Slack user(s).",
        });
      }
      if (url === "/api/standups" && init.method === "POST") return jsonResponse({ errors: ["Name can't be blank"], field_errors: { name: ["can't be blank"] } }, 422);
      return undefined;
    });
    renderApp("/manager/standups/new");

    const input = await screen.findByRole("combobox", { name: "Add people" });
    await user.type(input, "@ada,");
    const chips = screen.getByRole("list", { name: "People in this standup" });
    expect(within(chips).getByText("@ada")).toBeInTheDocument();
    expect(within(chips).getByText("looked up on save")).toBeInTheDocument();

    await user.click(within(chips).getByRole("button", { name: "Remove Maya Manager" }));
    expect(within(chips).getByText("removed on save")).toBeInTheDocument();
    await user.click(within(chips).getByRole("button", { name: "Restore Maya Manager" }));
    expect(within(chips).queryByText("removed on save")).toBeNull();
    await user.click(within(chips).getByRole("button", { name: "Remove Maya Manager" }));

    await user.type(input, "gra");
    const option = await screen.findByRole("option", { name: /Grace Hopper/ });
    expect(urls(fetchMock)).toContain("/api/people?platform=slack&q=gra");
    await user.click(option);
    expect(within(chips).getByText("Grace Hopper")).toBeInTheDocument();
    expect(input).toHaveValue("");

    await user.type(input, "U777");
    await user.click(screen.getByRole("button", { name: "Create standup" }));
    await screen.findByText("1 error prevented saving");
    const [body] = bodiesFor(fetchMock, "/api/standups");
    expect(body.standup.participants).toEqual([
      { id: null, platform_user_id: "U0MAYA", original_platform_user_id: "U0MAYA", display_name: "Maya Manager", cached_timezone: "America/New_York", active: true, _destroy: true },
      { id: null, platform_user_id: "@ada", original_platform_user_id: "", display_name: "", cached_timezone: "", active: true, _destroy: false },
      { id: null, platform_user_id: "U9GRACE", original_platform_user_id: "", display_name: "Grace Hopper", cached_timezone: "America/New_York", active: true, _destroy: false },
    ]);
    expect(body.standup.participant_handles).toBe("U777");
  });
});
