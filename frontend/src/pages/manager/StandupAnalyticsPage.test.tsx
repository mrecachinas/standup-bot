import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { insightsFixture, standupFixture } from "./insights/testFixtures";

const BASE = "/api/standups/7/analytics";

function insightsHandler(payload = insightsFixture()) {
  return (url: string, init: RequestInit) => {
    if (url.startsWith(BASE) && init.method === "GET") return jsonResponse(payload);
    return undefined;
  };
}

describe("StandupAnalyticsPage", () => {
  it("renders stats, charts, participation, blockers, the funnel and question summaries", async () => {
    const fetchMock = mockFetch(userBootstrap(), insightsHandler());
    renderApp("/manager/standups/7/analytics");

    expect(await screen.findByRole("heading", { name: "Daily standup", level: 1 })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Insights · Daily standup · Standup Bot"));
    expect(fetchMock.mock.calls.some(([url]) => url === `${BASE}?view=insights`)).toBe(true);

    expect(screen.getByRole("link", { name: "Insights" })).toHaveAttribute("aria-current", "page");
    const completion = screen.getByText("Completion rate").parentElement!;
    expect(completion).toHaveTextContent("75%");
    expect(within(completion).getByText("5 pts")).toBeInTheDocument();
    expect(screen.getByLabelText("Up")).toBeInTheDocument();
    expect(screen.getByText("vs. the previous 30 days")).toBeInTheDocument();
    expect(screen.getByText("/ 8")).toBeInTheDocument();
    expect(screen.getByText("12 min")).toBeInTheDocument();
    expect(screen.getByText("Oct 2 – Oct 31, 2026")).toBeInTheDocument();

    expect(screen.getByRole("img", { name: "Completion rate per run" })).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Responses per run" })).toBeInTheDocument();

    const participation = screen.getByRole("list", { name: "Participation by person" });
    const rows = within(participation).getAllByRole("listitem");
    expect(rows[0]).toHaveTextContent("Jane Smith");
    expect(rows[0]).toHaveTextContent("1 missed response");
    expect(rows[0]).toHaveTextContent("50%");
    expect(rows[1]).toHaveTextContent("No misses");

    const blockers = screen.getByRole("list", { name: "Blocker keywords" });
    expect(within(blockers).getByText("deploy")).toBeInTheDocument();

    expect(screen.getByText("Out of 4 check-ins started in this period")).toBeInTheDocument();
    expect(screen.getByText("Most drop-off happens at question 3: 1 check-in ended there without an answer.")).toBeInTheDocument();
    expect(screen.getByLabelText("2 answered, 1 skipped, 1 stopped before this question")).toBeInTheDocument();

    expect(screen.getByRole("heading", { name: "Answers by question" })).toBeInTheDocument();
    expect(screen.getByText("Fixed bugs")).toBeInTheDocument();
    expect(screen.getByText("Alex Doe · Oct 30")).toBeInTheDocument();
    expect(screen.getByText("No answers in this period.")).toBeInTheDocument();

    expect(screen.getByRole("link", { name: "Export CSV" })).toHaveAttribute("href", "/api/standups/7/analytics.csv?end_date=2026-10-31&start_date=2026-10-02");
    expect(screen.getByRole("link", { name: "Response history" })).toHaveAttribute("href", "/manager/standups/7/responses?start_date=2026-10-02&end_date=2026-10-31");
  });

  it("shows dashes and empty messages without data", async () => {
    const payload = insightsFixture({
      has_data: false,
      stats: { ...insightsFixture().insights.stats, completion_rate: 0, completion_rate_delta: null, completion_rate_delta_direction: null, completed_responses: 0, expected_responses: 0, average_response_time_label: null, runs_count: 0 },
      runs: [],
      completion_series: [],
      participants: [],
      blocker_keywords: [],
      question_funnel: { started: 0, started_label: "Out of 0 check-ins started in this period", biggest_drop: null, rows: [] },
      question_summaries: [],
    });
    mockFetch(userBootstrap(), insightsHandler(payload));
    renderApp("/manager/standups/7/analytics");

    expect(await screen.findByText("No active participants.")).toBeInTheDocument();
    expect(screen.getByText("No recurring blockers in this period.")).toBeInTheDocument();
    expect(screen.getByText("No check-ins were started in this period.")).toBeInTheDocument();
    expect(screen.getByText("No standup runs in this period yet.")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Answers by question" })).toBeNull();
    expect(screen.getAllByText("—").length).toBeGreaterThanOrEqual(2);
  });

  it("puts presets and a custom range in the URL and refetches", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), insightsHandler());
    const { router } = renderApp("/manager/standups/7/analytics");

    const sevenDays = await screen.findByRole("button", { name: "7 days" });
    expect(screen.getByRole("button", { name: "30 days" })).toHaveAttribute("aria-pressed", "true");
    await user.click(sevenDays);
    await waitFor(() => expect(router.state.location.search).toBe("?start_date=2026-10-25&end_date=2026-10-31"));
    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => url === `${BASE}?view=insights&start_date=2026-10-25&end_date=2026-10-31`)).toBe(true));

    const start = screen.getByLabelText("Start date");
    const end = screen.getByLabelText("End date");
    await user.clear(start);
    await user.type(start, "2026-09-01");
    await user.clear(end);
    await user.type(end, "2026-09-15");
    await user.click(screen.getByRole("button", { name: "Apply" }));

    await waitFor(() => expect(router.state.location.search).toBe("?start_date=2026-09-01&end_date=2026-09-15"));
    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => url === `${BASE}?view=insights&start_date=2026-09-01&end_date=2026-09-15`)).toBe(true));
  });

  it("warns when the range was limited", async () => {
    const base = insightsFixture().insights;
    mockFetch(userBootstrap(), insightsHandler(insightsFixture({ range: { ...base.range, limited: true } })));
    renderApp("/manager/standups/7/analytics?start_date=2020-01-01&end_date=2026-10-31");

    expect(await screen.findByText("Showing the most recent 365 days.")).toBeInTheDocument();
  });

  it("pauses the standup from the header", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === "/api/standups/7/pause" && init.method === "PATCH") return jsonResponse({ standup: standupFixture({ active: false }), notice: "Standup paused." });
      return insightsHandler()(url, init);
    });
    renderApp("/manager/standups/7/analytics");

    await user.click(await screen.findByRole("button", { name: "Pause Daily standup" }));

    expect(await screen.findByText("Standup paused.")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Resume Daily standup" })).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url, init]) => url === "/api/standups/7/pause" && init?.method === "PATCH")).toBe(true);
  });

  it("shows not found for a missing standup", async () => {
    mockFetch(userBootstrap(), (url) => (url.startsWith(BASE) ? jsonResponse({ error: "Not found" }, 404) : undefined));
    renderApp("/manager/standups/7/analytics");

    expect(await screen.findByRole("heading", { name: "Standup not found" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Back to standups" })).toHaveAttribute("href", "/manager/standups");
  });

  it("explains a forbidden standup", async () => {
    mockFetch(userBootstrap(), (url) => (url.startsWith(BASE) ? jsonResponse({ error: "You don't manage this standup." }, 403) : undefined));
    renderApp("/manager/standups/7/analytics");

    expect(await screen.findByRole("heading", { name: "You don't have access to this standup" })).toBeInTheDocument();
    expect(screen.getByText("You don't manage this standup.")).toBeInTheDocument();
  });
});
