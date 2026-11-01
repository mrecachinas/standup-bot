import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, memberBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { availabilityPayload, memberProfile, standupsPayload } from "./components/fixtures";

describe("MyStandupsPage", () => {
  it("shows stats and a card per standup", async () => {
    mockFetch(memberBootstrap(), (url) => (url === "/api/me/standups" ? jsonResponse(standupsPayload()) : undefined));
    renderApp("/me");

    expect(await screen.findByRole("heading", { level: 1, name: "My standups" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("My standups · Standup Bot"));
    expect(screen.getByText("Your check-ins across 2 standups. Answer them in your Slack DMs.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Set time away" })).toHaveAttribute("href", "/me/availability");

    expect(screen.getByText("1 active")).toBeInTheDocument();
    expect(screen.getByText("Your completion · 30 days")).toBeInTheDocument();
    expect(screen.getByText("8 of 10 check-ins")).toBeInTheDocument();
    expect(screen.getByText("Mon, Nov 2")).toBeInTheDocument();
    expect(screen.getByText("9:00 AM EST · Daily standup")).toBeInTheDocument();
    expect(screen.getByText("Available")).toBeInTheDocument();
    expect(screen.getByText("Getting check-ins as scheduled")).toBeInTheDocument();

    const daily = screen.getByRole("region", { name: "Daily standup" });
    expect(within(daily).getByText("#eng-standup")).toBeInTheDocument();
    expect(within(daily).getByText("Active")).toBeInTheDocument();
    expect(within(daily).getByText("Weekdays at 9:00 AM")).toBeInTheDocument();
    expect(within(daily).getByText("Mon, Nov 2 at 9:00 AM EST")).toBeInTheDocument();
    expect(within(daily).getByText("Answered")).toBeInTheDocument();
    expect(within(daily).getByText("80%")).toBeInTheDocument();
    expect(within(daily).getByRole("progressbar")).toHaveAttribute("aria-valuenow", "80");
    expect(within(daily).getByRole("img", { name: "Alex Kim and Bea Lopez" })).toBeInTheDocument();
    expect(within(daily).getByText("with 2 teammates")).toBeInTheDocument();
    expect(within(daily).getByRole("link", { name: "My answers in Daily standup" })).toHaveAttribute("href", "/me/responses?standup_id=7");

    const retro = screen.getByRole("region", { name: "Retro" });
    expect(within(retro).getByText("Standup paused")).toBeInTheDocument();
    expect(within(retro).getByText("No check-in today")).toBeInTheDocument();
    expect(within(retro).getByText("Not enough history yet")).toBeInTheDocument();
    expect(within(retro).getByText("Just you so far")).toBeInTheDocument();

    expect(screen.getByText(/Tip: in Slack, DM the bot/)).toBeInTheDocument();
    expect(screen.queryByText("I'm back")).toBeNull();
  });

  it("uses the member's platform label and handles empty stats", async () => {
    mockFetch(memberBootstrap(), (url) =>
      url === "/api/me/standups"
        ? jsonResponse(
            standupsPayload({
              member: { ...memberProfile, platform: "teams", platform_label: "Microsoft Teams" },
              stats: {
                ...standupsPayload().stats,
                standups_count: 0,
                active_count: 0,
                expected: 0,
                completed: 0,
                completion_rate: null,
                next_check_in: null,
              },
              standups: [],
            }),
          )
        : undefined,
    );
    renderApp("/me");

    expect(await screen.findByText("You're not in any standups yet")).toBeInTheDocument();
    expect(screen.getByText("Your check-ins across 0 standups. Answer them in your Microsoft Teams DMs.")).toBeInTheDocument();
    expect(screen.getByText("Nothing scheduled")).toBeInTheDocument();
    expect(screen.getByText("0 of 0 check-ins")).toBeInTheDocument();
    expect(screen.getByText(/Tip: in Microsoft Teams, DM the bot/)).toBeInTheDocument();
  });

  it("shows the away banner and clears time away", async () => {
    const user = userEvent.setup();
    let away = true;
    const fetchMock = mockFetch(memberBootstrap(), (url, init) => {
      if (url === "/api/me/availability/clear" && init.method === "DELETE") {
        away = false;
        return jsonResponse({ ...availabilityPayload(), notice: "Welcome back. You'll get your next check-ins as usual." });
      }
      if (url === "/api/me/standups") {
        return jsonResponse(
          away
            ? standupsPayload({
                away_until: "2026-11-06",
                away_until_label: "Friday, November 6",
                stats: { ...standupsPayload().stats, status_label: "Away", status_detail: "Back Nov 7" },
              })
            : standupsPayload(),
        );
      }
      return undefined;
    });
    renderApp("/me");

    expect(await screen.findByText("Friday, November 6")).toBeInTheDocument();
    expect(screen.getByText("Back Nov 7")).toBeInTheDocument();
    // Primer's Banner renders its actions twice (inline and stacked layouts); CSS shows one.
    await user.click(screen.getAllByRole("button", { name: "I'm back" })[0]);

    expect(await screen.findByText("Welcome back. You'll get your next check-ins as usual.")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("button", { name: "I'm back" })).toBeNull());
    expect(fetchMock.mock.calls.some(([url, init]) => url === "/api/me/availability/clear" && init?.method === "DELETE")).toBe(true);
    expect(screen.getByText("Available")).toBeInTheDocument();
  });

  it("shows the server's error when the member can't see the page", async () => {
    mockFetch(memberBootstrap(), (url) =>
      url === "/api/me/standups" ? jsonResponse({ error: "Sign in with Slack or Microsoft to see your own standups." }, 403) : undefined,
    );
    renderApp("/me");

    expect(await screen.findByText("Sign in with Slack or Microsoft to see your own standups.")).toBeInTheDocument();
    expect(screen.getByText("You can't see these standups")).toBeInTheDocument();
  });
});
