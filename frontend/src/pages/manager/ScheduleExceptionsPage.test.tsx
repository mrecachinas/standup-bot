import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { schedulePayload, standupFixture } from "./roster/testFixtures";

const PAGE = "/manager/standups/7/schedule_exceptions";
const API = "/api/standups/7/schedule_exceptions";

type FetchMock = ReturnType<typeof mockFetch>;

function callsTo(fetchMock: FetchMock, method: string, url: string) {
  return fetchMock.mock.calls.filter(([callUrl, init]) => String(callUrl) === url && (init?.method ?? "GET") === method);
}

function bodyOf(fetchMock: FetchMock, method: string, url: string) {
  const call = callsTo(fetchMock, method, url).at(-1);
  return call ? JSON.parse(String(call[1]!.body ?? "null")) : undefined;
}

function setup(handler?: (url: string, init: RequestInit) => Response | undefined, payload = schedulePayload()) {
  return mockFetch(userBootstrap(), (url, init) => handler?.(url, init) ?? (url.startsWith(API) && init.method === "GET" ? jsonResponse(payload) : undefined));
}

const created = (notice: string) => jsonResponse({ schedule_exception: schedulePayload().schedule_exceptions[0], notice }, 201);

describe("ScheduleExceptionsPage", () => {
  it("shows upcoming runs, exceptions, the regular schedule and notes", async () => {
    setup();
    renderApp(PAGE);

    const upcoming = await screen.findByRole("list", { name: "Upcoming runs" });
    await waitFor(() => expect(document.title).toBe("Schedule · Daily standup · Standup Bot"));
    expect(screen.getByRole("link", { name: "Schedule" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByText("Includes skipped and moved dates")).toBeInTheDocument();
    expect(screen.getByLabelText("Show times in")).toHaveValue("UTC");

    const items = within(upcoming).getAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(items[0]).toHaveTextContent("Monday, November 2, 2026 at 9:30 AM UTC");
    expect(items[0]).toHaveTextContent("Scheduled");
    expect(within(items[0]).getByRole("button", { name: "Skip November 2, 2026" })).toBeInTheDocument();
    expect(items[1]).toHaveTextContent("Election day");
    expect(items[1]).toHaveTextContent("Holiday");
    expect(within(items[1]).queryByRole("button", { name: /Skip/ })).toBeNull();

    const table = screen.getByRole("table", { name: "Exceptions" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(rows[1]).toHaveTextContent("November 3, 2026");
    expect(rows[1]).toHaveTextContent("Election day");
    expect(rows[2]).toHaveTextContent("Rescheduled");
    expect(rows[2]).toHaveTextContent("Fri, Nov 6 at 2:00 PM UTC");

    expect(screen.getByRole("heading", { name: "Regular schedule" })).toBeInTheDocument();
    expect(screen.getByText("Weekdays at 9:30 AM", { selector: "p" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Edit" })).toHaveAttribute("href", "/manager/standups/7/edit#schedule");
    expect(screen.getByText("Monday, November 2, 2026 at 9:30 AM UTC", { selector: "strong" })).toBeInTheDocument();
    expect(screen.getByLabelText(/New date/)).toHaveValue("2026-11-02");
    expect(screen.getByLabelText(/New time/)).toHaveValue("09:30");
    expect(screen.getByText(/Skipped, holiday, and canceled dates do not create prompts/)).toBeInTheDocument();
  });

  it("shows empty states", async () => {
    setup(undefined, schedulePayload({ upcoming_occurrences: [], next_occurrence: null, schedule_exceptions: [] }));
    renderApp(PAGE);

    expect(await screen.findByText("No upcoming occurrences could be calculated for this schedule.")).toBeInTheDocument();
    expect(screen.getByText("No skipped, holiday, or moved dates yet.")).toBeInTheDocument();
    expect(screen.getByText("There's no upcoming run to move.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cancel next run" })).toBeNull();
  });

  it("changes the preview timezone through the URL", async () => {
    const user = userEvent.setup();
    const fetchMock = setup();
    const { router } = renderApp(PAGE);

    await user.selectOptions(await screen.findByLabelText("Show times in"), "London");

    await waitFor(() => expect(router.state.location.search).toBe("?preview_timezone=London"));
    await waitFor(() => expect(callsTo(fetchMock, "GET", `${API}?preview_timezone=London`)).toHaveLength(1));
  });

  it("skips an upcoming run", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) => (url === API && init.method === "POST" ? created("Skipped date saved for November 2, 2026.") : undefined));
    renderApp(PAGE);

    await user.click(await screen.findByRole("button", { name: "Skip November 2, 2026" }));

    expect(await screen.findByText("Skipped date saved for November 2, 2026.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", API)).toEqual({ schedule_exception: { exception_type: "skipped_date", original_date: "2026-11-02", reason: "Skipped" } });
    await waitFor(() => expect(callsTo(fetchMock, "GET", API)).toHaveLength(2));
  });

  it("saves a holiday and shows field errors", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url, init) => {
      if (url !== API || init.method !== "POST") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse(
            {
              errors: ["Original date must be a scheduled date for this standup"],
              field_errors: { original_date: ["must be a scheduled date for this standup"] },
            },
            422,
          )
        : created("Holiday saved for November 4, 2026.");
    });
    renderApp(PAGE);

    const form = (await screen.findByRole("heading", { name: "Skip a date" })).closest("section")!;
    const date = within(form).getByLabelText(/Date/);
    await user.type(date, "2026-11-08");
    await user.selectOptions(within(form).getByLabelText("Type"), "holiday");
    await user.type(within(form).getByLabelText("Reason"), "Offsite");
    await user.click(within(form).getByRole("button", { name: "Save exception" }));

    expect(await within(form).findByText("Date must be a scheduled date for this standup")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", API)).toEqual({ schedule_exception: { exception_type: "holiday", original_date: "2026-11-08", reason: "Offsite" } });

    await user.clear(date);
    await user.type(date, "2026-11-04");
    await user.click(within(form).getByRole("button", { name: "Save exception" }));
    expect(await screen.findByText("Holiday saved for November 4, 2026.")).toBeInTheDocument();
    expect(within(form).getByLabelText(/Date/)).toHaveValue("");
    expect(within(form).queryByText("Date must be a scheduled date for this standup")).toBeNull();
  });

  it("moves the next run and shows timezone errors", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url, init) => {
      if (url !== API || init.method !== "POST") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse({ errors: ["Rescheduled timezone is not valid"], field_errors: { rescheduled_timezone: ["is not valid"] } }, 422)
        : created("Rescheduled saved for November 2, 2026.");
    });
    renderApp(PAGE);

    const form = (await screen.findByRole("heading", { name: "Move the next run" })).closest("section")!;
    const time = within(form).getByLabelText(/New time/);
    await user.clear(time);
    await user.type(time, "14:15");
    await user.selectOptions(within(form).getByLabelText("Timezone"), "Eastern Time (US & Canada)");
    await user.type(within(form).getByLabelText("Reason"), "Team offsite");
    await user.click(within(form).getByRole("button", { name: "Move run" }));

    expect(await within(form).findByText("Timezone is not valid")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", API)).toEqual({
      schedule_exception: {
        exception_type: "rescheduled",
        original_date: "2026-11-02",
        rescheduled_date: "2026-11-02",
        rescheduled_time: "14:15",
        rescheduled_timezone: "Eastern Time (US & Canada)",
        reason: "Team offsite",
      },
    });

    await user.click(within(form).getByRole("button", { name: "Move run" }));
    expect(await screen.findByText("Rescheduled saved for November 2, 2026.")).toBeInTheDocument();
  });

  it("cancels the next run after confirming", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) => (url === API && init.method === "POST" ? created("Cancelled saved for November 2, 2026.") : undefined));
    renderApp(PAGE);

    await user.click(await screen.findByRole("button", { name: "Cancel next run" }));
    const dialog = await screen.findByRole("alertdialog", { name: "Cancel the next run?" });
    expect(dialog).toHaveTextContent("Cancel the run on Monday, November 2?");
    await user.click(within(dialog).getByRole("button", { name: "Cancel run" }));

    expect(await screen.findByText("Cancelled saved for November 2, 2026.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", API)).toEqual({
      schedule_exception: { exception_type: "cancelled", original_date: "2026-11-02", reason: "One-off cancellation" },
    });
  });

  it("removes an exception and reports failures", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url, init) => {
      if (url !== `${API}/31` || init.method !== "DELETE") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse({ error: "That page or record doesn't exist." }, 404)
        : jsonResponse({ schedule_exception: schedulePayload().schedule_exceptions[0], notice: "Removed the holiday exception for November 3, 2026." });
    });
    renderApp(PAGE);

    const remove = await screen.findByRole("button", { name: "Remove the holiday exception for November 3, 2026" });
    await user.click(remove);
    expect(await screen.findByText("Couldn't remove the exception")).toBeInTheDocument();

    await user.click(remove);
    expect(await screen.findByText("Removed the holiday exception for November 3, 2026.")).toBeInTheDocument();
    expect(screen.queryByText("Couldn't remove the exception")).toBeNull();
    expect(callsTo(fetchMock, "DELETE", `${API}/31`)).toHaveLength(2);
  });

  it("pauses from the regular schedule card", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/pause" && init.method === "PATCH"
        ? jsonResponse({ standup: standupFixture({ active: false }), notice: "Paused Daily standup." })
        : undefined,
    );
    renderApp(PAGE);

    await user.click(await screen.findByRole("button", { name: "Pause standup" }));
    expect(await screen.findByText("Paused Daily standup.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Resume standup" })).toBeInTheDocument();
    expect(callsTo(fetchMock, "PATCH", "/api/standups/7/pause")).toHaveLength(1);
  });

  it("shows not found", async () => {
    mockFetch(userBootstrap(), (url) => (url.startsWith(API) ? jsonResponse({ error: "Not found" }, 404) : undefined));
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "Standup not found" })).toBeInTheDocument();
  });
});
