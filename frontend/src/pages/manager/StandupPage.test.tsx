import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { standupFixture, standupOverviewFixture } from "./standups/testFixtures";

describe("StandupPage", () => {
  it("shows the overview: stats, runs, latest answers, questions, upcoming runs, exceptions and participants", async () => {
    const fetchMock = mockFetch(userBootstrap(), (url) => (url === "/api/standups/7?include=overview" ? jsonResponse(standupOverviewFixture()) : undefined));
    renderApp("/manager/standups/7");

    expect(await screen.findByRole("heading", { name: "Daily standup", level: 1 })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Daily standup · Standup Bot"));
    expect(fetchMock.mock.calls.map(([url]) => String(url))).toContain("/api/standups/7?include=overview");
    const tabs = screen.getByRole("navigation", { name: "Daily standup sections" });
    expect(within(tabs).getByRole("link", { name: "Overview" })).toHaveAttribute("aria-current", "page");

    expect(screen.getByText("Completion · 14 days")).toBeInTheDocument();
    expect(screen.getByText("25 pts")).toHaveAttribute("title", "Compared with the previous period");
    expect(screen.getByText("6 of 8 responses")).toBeInTheDocument();
    expect(screen.getByText("12 minutes")).toBeInTheDocument();
    expect(screen.getByText("1 inactive")).toBeInTheDocument();
    expect(screen.getByText("Mon, Nov 2")).toBeInTheDocument();
    expect(screen.getByText("9:30 AM in each person's timezone")).toBeInTheDocument();

    expect(screen.getByRole("img", { name: "Responses per run for Daily standup" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "View insights" })).toHaveAttribute("href", "/manager/standups/7/analytics");

    const latest = screen.getByRole("list", { name: "Latest run responses" });
    expect(screen.getByText("October 30, 2026")).toBeInTheDocument();
    expect(within(latest).getByText("Ada Lovelace")).toBeInTheDocument();
    expect(within(latest).getByText("Completed")).toBeInTheDocument();
    expect(within(latest).getByText("Shipped the engine")).toBeInTheDocument();
    expect(within(latest).getByText("Pending")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "All responses" })).toHaveAttribute("href", "/manager/standups/7/responses");

    const questions = screen.getByRole("region", { name: "Questions" });
    expect(within(questions).getAllByRole("listitem").map((item) => item.textContent)).toEqual(["What did you do yesterday?", "What will you do today?"]);
    expect(within(questions).getByRole("link", { name: "Edit" })).toHaveAttribute("href", "/manager/standups/7/edit#questions");

    const upcoming = screen.getByRole("list", { name: "Upcoming runs" });
    expect(within(upcoming).getAllByRole("listitem")).toHaveLength(2);
    expect(within(upcoming).getByText("Monday")).toBeInTheDocument();

    const exceptions = screen.getByRole("list", { name: "Schedule exceptions" });
    expect(within(exceptions).getByText("Holiday")).toBeInTheDocument();
    expect(within(exceptions).getByText("Thanksgiving")).toBeInTheDocument();

    const people = screen.getByRole("list", { name: "Active participants" });
    expect(within(people).getByText("Grace Hopper")).toBeInTheDocument();
    expect(within(people).getByText("New York")).toBeInTheDocument();
  });

  it("shows empty states for a paused standup with no runs", async () => {
    const payload = standupOverviewFixture(
      {
        completion: { rate: null, label: "—", tone: null, completed: 0, expected: 0, sub_label: "0 of 0 responses", previous_rate: null, delta: null },
        next_run: { scheduled_at: null, label: "Paused", sub_label: "Resume to schedule runs" },
        runs: [],
        runs_have_pending: false,
        latest_run: { date: null, date_label: "No runs yet", responses: [] },
        sidebar_participants: [],
        upcoming: { occurrences: [], preview_timezone: "UTC", error: null, empty_message: "No upcoming runs.", paused: true, paused_message: "This standup is paused. Resume it to schedule runs." },
        schedule_exceptions: [],
      },
      { active: false },
    );
    mockFetch(userBootstrap(), (url) => (url === "/api/standups/7?include=overview" ? jsonResponse(payload) : undefined));
    renderApp("/manager/standups/7");

    expect(await screen.findByText("Responses will show up here after the first run.")).toBeInTheDocument();
    expect(screen.getByText("This standup is paused. Resume it to schedule runs.")).toBeInTheDocument();
    expect(screen.getByText("No one has been added yet.")).toBeInTheDocument();
    expect(screen.getByText("No standup runs in this period yet.")).toBeInTheDocument();
    expect(screen.getByText("Resume to schedule runs")).toBeInTheDocument();
    expect(screen.queryByRole("list", { name: "Schedule exceptions" })).toBeNull();
  });

  it("pauses the standup and refreshes the sidebar", async () => {
    const user = userEvent.setup();
    let paused = false;
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === "/api/standups/7/pause" && init.method === "PATCH") {
        paused = true;
        return jsonResponse({ standup: standupFixture({ active: false }), notice: "Daily standup was paused." });
      }
      if (url === "/api/standups/7?include=overview") return jsonResponse(standupOverviewFixture({}, { active: !paused }));
      return undefined;
    });
    renderApp("/manager/standups/7");

    await user.click(await screen.findByRole("button", { name: "Pause Daily standup" }));
    expect(await screen.findByText("Daily standup was paused.")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Resume Daily standup" })).toBeInTheDocument();
    const patches = fetchMock.mock.calls.filter(([, init]) => init?.method === "PATCH").map(([url]) => url);
    expect(patches).toEqual(["/api/standups/7/pause"]);
    expect(fetchMock.mock.calls.filter(([url]) => url === "/api/session").length).toBeGreaterThan(1);
  });

  it("says when the standup doesn't exist or isn't yours", async () => {
    mockFetch(userBootstrap(), (url) => {
      if (url === "/api/standups/404?include=overview") return jsonResponse({ error: "Not found" }, 404);
      if (url === "/api/standups/403?include=overview") return jsonResponse({ error: "Forbidden" }, 403);
      return undefined;
    });
    const { router } = renderApp("/manager/standups/404");
    expect(await screen.findByRole("heading", { name: "Standup not found" })).toBeInTheDocument();

    await router.navigate("/manager/standups/403");
    expect(await screen.findByRole("heading", { name: "You don't manage this standup" })).toBeInTheDocument();
  });
});
