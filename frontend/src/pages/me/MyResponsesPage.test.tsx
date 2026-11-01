import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, memberBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { memberProfile, responsesPayload } from "./components/fixtures";

describe("MyResponsesPage", () => {
  it("lists recent check-ins with answers", async () => {
    mockFetch(memberBootstrap(), (url) => (url === "/api/me/responses" ? jsonResponse(responsesPayload()) : undefined));
    renderApp("/me/responses");

    expect(await screen.findByRole("heading", { level: 1, name: "My responses" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("My responses · Standup Bot"));
    expect(screen.getByText("Your most recent check-ins.")).toBeInTheDocument();

    const items = within(screen.getByRole("region", { name: "Check-ins" })).getAllByRole("listitem");
    expect(items).toHaveLength(3);
    expect(within(items[0]).getByText("Daily standup")).toBeInTheDocument();
    expect(within(items[0]).getByText("Friday, October 30, 2026")).toBeInTheDocument();
    expect(within(items[0]).getByText("Answered")).toBeInTheDocument();
    expect(within(items[0]).getByText("What did you do yesterday?")).toBeInTheDocument();
    expect(within(items[0]).getByText("Shipped the console")).toBeInTheDocument();
    expect(within(items[0]).getByText("No answer")).toBeInTheDocument();
    expect(within(items[1]).getByText("Pending")).toBeInTheDocument();
    expect(within(items[1]).getByText("Waiting for your answers in Slack.")).toBeInTheDocument();
    expect(within(items[2]).getByText("No answers recorded.")).toBeInTheDocument();
    expect(screen.queryByText(/most recent check-ins\.$/, { selector: "p" })).toBeNull();
  });

  it("filters by standup through the URL", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(memberBootstrap(), (url) => {
      if (url === "/api/me/responses") return jsonResponse(responsesPayload());
      if (url === "/api/me/responses?standup_id=8") {
        const all = responsesPayload();
        return jsonResponse({ ...all, standup: { id: 8, name: "Retro" }, responses: all.responses.filter((response) => response.standup_id === 8) });
      }
      return undefined;
    });
    const { router } = renderApp("/me/responses");

    const all = await screen.findByRole("button", { name: "All" });
    expect(all).toHaveAttribute("aria-pressed", "true");
    await user.click(screen.getByRole("button", { name: "Retro" }));

    await waitFor(() => expect(router.state.location.search).toBe("?standup_id=8"));
    expect(await screen.findByText("Your most recent check-ins in Retro.")).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByRole("region", { name: "Check-ins" })).getAllByRole("listitem")).toHaveLength(2));
    expect(screen.getByRole("button", { name: "Retro" })).toHaveAttribute("aria-pressed", "true");
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/me/responses?standup_id=8")).toBe(true);

    await user.click(screen.getByRole("button", { name: "All" }));
    await waitFor(() => expect(router.state.location.search).toBe(""));
    expect(await screen.findByText("Your most recent check-ins.")).toBeInTheDocument();
  });

  it("reads the standup filter from the URL", async () => {
    mockFetch(memberBootstrap(), (url) =>
      url === "/api/me/responses?standup_id=7" ? jsonResponse(responsesPayload({ standup: { id: 7, name: "Daily standup" }, responses: [] })) : undefined,
    );
    renderApp("/me/responses?standup_id=7");

    expect(await screen.findByText("Your most recent check-ins in Daily standup.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Daily standup" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("heading", { name: "No check-ins yet" })).toBeInTheDocument();
    expect(screen.getByText("Your answers will show up here after your first standup.")).toBeInTheDocument();
  });

  it("hides the filter for one standup, shows the limit note and uses the member's platform", async () => {
    const base = responsesPayload();
    mockFetch(memberBootstrap(), (url) =>
      url === "/api/me/responses"
        ? jsonResponse({
            ...base,
            member: { ...memberProfile, platform: "teams", platform_label: "Microsoft Teams" },
            standups: [{ id: 8, name: "Retro" }],
            responses: base.responses.filter((response) => response.standup_id === 8),
            limit: 2,
            limited: true,
          })
        : undefined,
    );
    renderApp("/me/responses");

    expect(await screen.findByText("Showing your 2 most recent check-ins.")).toBeInTheDocument();
    expect(screen.getByText("Waiting for your answers in Microsoft Teams.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "All" })).toBeNull();
  });
});
