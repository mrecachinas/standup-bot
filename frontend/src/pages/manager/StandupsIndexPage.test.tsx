import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { overviewFixture, standupFixture } from "./standups/testFixtures";

function requests(fetchMock: ReturnType<typeof mockFetch>, method = "GET") {
  return fetchMock.mock.calls.filter(([, init]) => (init?.method ?? "GET") === method).map(([url]) => String(url));
}

describe("StandupsIndexPage", () => {
  it("shows the stats, chart, needs-attention list and standups table", async () => {
    const fetchMock = mockFetch(userBootstrap(), (url) => (url.startsWith("/api/overview") ? jsonResponse(overviewFixture()) : undefined));
    renderApp("/manager/standups");

    expect(await screen.findByRole("heading", { name: "Overview", level: 1 })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Overview · Standup Bot"));
    expect(requests(fetchMock)).toContain("/api/overview?visibility=all&period_days=14");
    expect(screen.getByText("How your standups are doing over the last 14 days.")).toBeInTheDocument();

    expect(await screen.findByText("Active standups")).toBeInTheDocument();
    expect(screen.getByText("1 paused")).toBeInTheDocument();
    expect(screen.getByText("Across 2 standups")).toBeInTheDocument();
    expect(screen.getByText("6 of 8 expected")).toBeInTheDocument();
    expect(screen.getByText("1 paused · 1 under 60%")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Responses by day across all standups" })).toBeInTheDocument();

    const attention = screen.getByRole("region", { name: "Needs attention" });
    expect(within(attention).getByRole("link", { name: "Retro" })).toHaveAttribute("href", "/manager/standups/8");
    expect(within(attention).getByRole("button", { name: "Resume Retro" })).toBeInTheDocument();

    const table = screen.getByRole("table", { name: "Standups" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(within(rows[1]).getByRole("link", { name: "Daily standup" })).toHaveAttribute("href", "/manager/standups/7");
    expect(within(rows[1]).getByText("#eng-standup")).toBeInTheDocument();
    expect(within(rows[1]).getByText("Weekdays at 9:30 AM")).toBeInTheDocument();
    expect(within(rows[1]).getByText("Next in about 22 hours")).toBeInTheDocument();
    expect(within(rows[1]).getByText("2 active participants")).toBeInTheDocument();
    expect(within(rows[1]).getByText("75%")).toBeInTheDocument();
    expect(within(rows[1]).getByText("6 of 8 responses")).toBeInTheDocument();
    expect(within(rows[1]).getByRole("img", { name: "Completion trend: 50%, 75%, 100%" })).toBeInTheDocument();
    expect(within(rows[1]).getByText("Oct 30 · 1 of 2 answered")).toBeInTheDocument();
    expect(within(rows[1]).getByText("Pending")).toBeInTheDocument();

    expect(within(rows[2]).getByText("Paused")).toBeInTheDocument();
    expect(within(rows[2]).getByText("None yet")).toBeInTheDocument();
    expect(within(rows[2]).getAllByText("No runs yet")).toHaveLength(2);
    expect(within(rows[2]).getByText("Not scheduled")).toBeInTheDocument();
  });

  it("shows the first-standup empty state", async () => {
    mockFetch(userBootstrap(), (url) =>
      url.startsWith("/api/overview") ? jsonResponse(overviewFixture({ empty: true, standups: [], needs_attention: [], daily_totals: [] })) : undefined,
    );
    renderApp("/manager/standups");

    expect(await screen.findByRole("heading", { name: "Create your first standup" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Connect a chat app" })).toHaveAttribute("href", "/manager/integrations");
    expect(screen.getAllByRole("link", { name: "New standup" })[0]).toHaveAttribute("href", "/manager/standups/new");
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("filters by visibility and period", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url) => {
      if (url === "/api/overview?visibility=paused&period_days=14") {
        return jsonResponse(overviewFixture({ visibility: "paused", standups: [], empty_list_message: "No paused standups." }));
      }
      if (url.startsWith("/api/overview")) return jsonResponse(overviewFixture());
      return undefined;
    });
    const { router } = renderApp("/manager/standups");

    await user.click(await screen.findByRole("button", { name: "Paused" }));
    expect(await screen.findByText("No paused standups.")).toBeInTheDocument();
    expect(router.state.location.search).toBe("?visibility=paused");

    await user.selectOptions(screen.getByLabelText("Period"), "30");
    await waitFor(() => expect(requests(fetchMock)).toContain("/api/overview?visibility=paused&period_days=30"));
  });

  it("resumes a paused standup from the needs-attention list", async () => {
    const user = userEvent.setup();
    let resumed = false;
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === "/api/standups/8/resume" && init.method === "PATCH") {
        resumed = true;
        return jsonResponse({ standup: standupFixture({ id: 8, name: "Retro", active: true }), notice: "Retro was resumed." });
      }
      if (url.startsWith("/api/overview")) return jsonResponse(overviewFixture(resumed ? { needs_attention: [] } : {}));
      return undefined;
    });
    renderApp("/manager/standups");

    await user.click(await screen.findByRole("button", { name: "Resume Retro" }));
    expect(await screen.findByText("Retro was resumed.")).toBeInTheDocument();
    expect(requests(fetchMock, "PATCH")).toEqual(["/api/standups/8/resume"]);
    expect(await screen.findByText("All standups are running and above 60% completion.")).toBeInTheDocument();
    // The sidebar's standup list is refreshed too.
    expect(requests(fetchMock).filter((url) => url === "/api/session").length).toBeGreaterThan(1);
  });

  it("shows three standups that need attention and the rest in a dialog", async () => {
    const user = userEvent.setup();
    const needsAttention = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"].map((name, index) => ({
      standup_id: 20 + index,
      name,
      active: true,
      reason: "0% completion over 14 days",
      tone: "danger" as const,
    }));
    mockFetch(userBootstrap(), (url) => (url.startsWith("/api/overview") ? jsonResponse(overviewFixture({ needs_attention: needsAttention })) : undefined));
    renderApp("/manager/standups");

    const card = (await screen.findByRole("heading", { name: "Needs attention", level: 2 })).closest("section")!;
    expect(within(card).getAllByRole("listitem").map((item) => within(item).getByRole("link").textContent)).toEqual(["Alpha", "Bravo", "Charlie"]);

    await user.click(within(card).getByRole("button", { name: "Show all 5" }));
    const dialog = await screen.findByRole("dialog", { name: "Needs attention" });
    expect(within(dialog).getAllByRole("listitem")).toHaveLength(5);
    expect(within(dialog).getByRole("link", { name: "Echo" })).toHaveAttribute("href", "/manager/standups/24");
  });

  it("doesn't offer to show more when every standup fits", async () => {
    mockFetch(userBootstrap(), (url) => (url.startsWith("/api/overview") ? jsonResponse(overviewFixture()) : undefined));
    renderApp("/manager/standups");

    expect(await screen.findByRole("button", { name: "Resume Retro" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^Show all/ })).not.toBeInTheDocument();
  });

  it("pauses a standup from its row menu, which also links to every tab", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === "/api/standups/7/pause" && init.method === "PATCH") {
        return jsonResponse({ standup: standupFixture({ active: false }), notice: "Daily standup was paused." });
      }
      if (url.startsWith("/api/overview")) return jsonResponse(overviewFixture());
      return undefined;
    });
    renderApp("/manager/standups");

    await user.click(await screen.findByRole("button", { name: "Actions for Daily standup" }));
    const menu = await screen.findByRole("menu");
    expect(within(menu).getByRole("menuitem", { name: "Edit" })).toHaveAttribute("href", "/manager/standups/7/edit");
    expect(within(menu).getByRole("menuitem", { name: "Schedule" })).toHaveAttribute("href", "/manager/standups/7/schedule_exceptions");
    await user.click(within(menu).getByRole("menuitem", { name: "Pause" }));

    expect(await screen.findByText("Daily standup was paused.")).toBeInTheDocument();
    expect(requests(fetchMock, "PATCH")).toEqual(["/api/standups/7/pause"]);
  });

  it("shows an error when the overview can't load", async () => {
    mockFetch(userBootstrap(), (url) => (url.startsWith("/api/overview") ? jsonResponse({ error: "Boom" }, 500) : undefined));
    renderApp("/manager/standups");

    expect(await screen.findByText("Couldn't load your standups")).toBeInTheDocument();
    expect(screen.getByText("Boom")).toBeInTheDocument();
  });
});
