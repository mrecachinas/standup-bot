import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { channelResult, chatStatusFixture, connectionResult, integrationsFixture, userResult } from "./insights/testFixtures";

describe("IntegrationsPage", () => {
  it("renders platform tabs, app status, lookup and the standups list", async () => {
    mockFetch(userBootstrap(), (url) => (url === "/api/integrations" ? jsonResponse(integrationsFixture()) : undefined));
    renderApp("/manager/integrations");

    expect(await screen.findByRole("heading", { name: "Slack app status" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Integrations", level: 1 })).toBeInTheDocument();
    expect(screen.getByText("Connection health and workspace lookup for each chat platform. Secrets are never shown.")).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Integrations · Standup Bot"));

    const tabs = screen.getByRole("navigation", { name: "Chat platforms" });
    const slack = within(tabs).getByRole("link", { name: /Slack/ });
    const teams = within(tabs).getByRole("link", { name: /Microsoft Teams/ });
    expect(slack).toHaveAttribute("aria-current", "page");
    expect(slack).toHaveTextContent("Connected");
    expect(teams).toHaveAttribute("href", "/manager/integrations?platform=teams");
    expect(teams).toHaveTextContent("Not set up");

    expect(within(screen.getByRole("list", { name: "Slack credentials" })).getAllByRole("listitem")).toHaveLength(3);
    expect(screen.getByText("Slack API authentication succeeded.")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Look up Slack channels and people" })).toBeInTheDocument();
    expect(screen.getByLabelText("Search channels")).toHaveAttribute("placeholder", "Search channels by name or ID");
    expect(screen.getByLabelText("Search people")).toHaveAttribute("placeholder", "Search by name, @username, or ID");

    const standups = screen.getByRole("list", { name: "Standups" });
    const rows = within(standups).getAllByRole("listitem");
    expect(rows[0]).toHaveTextContent("Daily standup");
    expect(rows[0]).toHaveTextContent("Slack · #standup (C0123)");
    expect(within(rows[0]).getByRole("img", { name: "Active" })).toBeInTheDocument();
    expect(within(rows[1]).getByRole("img", { name: "Paused" })).toBeInTheDocument();
    expect(within(rows[0]).getByRole("link", { name: "Configure Daily standup" })).toHaveAttribute("href", "/manager/standups/7/chat_setup");
  });

  it("switches platform through the URL", async () => {
    const user = userEvent.setup();
    const teams = integrationsFixture({
      platform: "teams",
      integration_status: chatStatusFixture({
        platform: "teams",
        label: "Microsoft Teams",
        title: "Microsoft Teams app status",
        configured: false,
        status_label: "Needs setup",
        status_tone: "warning",
        connection: connectionResult({ success: false, status: "error", message: "Microsoft Teams isn't configured.", action: "Set MICROSOFT_APP_ID.", metadata: null }),
      }),
      copy: { channel_search_placeholder: "Search by team or channel name", user_search_placeholder: "Search by name or email" },
      standups: [],
    });
    const fetchMock = mockFetch(userBootstrap(), (url) => {
      if (url === "/api/integrations?platform=teams") return jsonResponse(teams);
      if (url === "/api/integrations") return jsonResponse(integrationsFixture());
      return undefined;
    });
    const { router } = renderApp("/manager/integrations");

    await user.click(await screen.findByRole("link", { name: /Microsoft Teams/ }));

    await waitFor(() => expect(router.state.location.search).toBe("?platform=teams"));
    expect(await screen.findByRole("heading", { name: "Microsoft Teams app status" })).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/integrations?platform=teams")).toBe(true);
    expect(screen.getByText("Next step: Set MICROSOFT_APP_ID.")).toBeInTheDocument();
    expect(screen.getByLabelText("Search people")).toHaveAttribute("placeholder", "Search by name or email");
    expect(screen.getByText("No standups are assigned to you yet.")).toBeInTheDocument();
  });

  it("searches channels and people", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url) => {
      if (url === "/api/integrations?platform=slack&channel_query=eng&discover=channels") return jsonResponse(integrationsFixture({ channel_query: "eng", channel_result: channelResult() }));
      if (url === "/api/integrations?platform=slack&discover=users") return jsonResponse(integrationsFixture({ user_result: userResult() }));
      if (url === "/api/integrations") return jsonResponse(integrationsFixture());
      return undefined;
    });
    const { router } = renderApp("/manager/integrations");

    await user.type(await screen.findByLabelText("Search channels"), "eng");
    await user.click(screen.getByRole("button", { name: "Find channels" }));

    await waitFor(() => expect(router.state.location.search).toBe("?platform=slack&discover=channels&channel_query=eng"));
    const channels = await screen.findByRole("list", { name: "Channel results" });
    expect(within(channels).getByText("eng-standup")).toBeInTheDocument();
    expect(within(channels).queryByRole("button")).toBeNull();

    await user.click(screen.getByRole("button", { name: "Find users" }));
    const people = await screen.findByRole("list", { name: "People results" });
    expect(within(people).getByText("Priya Patel")).toBeInTheDocument();
    expect(within(people).getByText("U777 · @priya · Europe/London")).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/integrations?platform=slack&discover=users")).toBe(true);
  });

  it("shows a load error with a retry", async () => {
    mockFetch(userBootstrap(), (url) => (url === "/api/integrations" ? jsonResponse({ error: "Boom" }, 500) : undefined));
    renderApp("/manager/integrations");

    expect(await screen.findByText("Couldn't load integrations")).toBeInTheDocument();
    expect(screen.getAllByRole("button", { name: "Try again" }).length).toBeGreaterThan(0);
  });
});
