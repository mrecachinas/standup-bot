import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { channelResult, chatSetupFixture, chatStatusFixture, connectionResult, standupFixture } from "./insights/testFixtures";

const BASE = "/api/standups/7/chat_setup";

function requestBody(fetchMock: ReturnType<typeof mockFetch>, method: string, url: string) {
  const call = fetchMock.mock.calls.find(([callUrl, init]) => callUrl === url && init?.method === method);
  return call ? JSON.parse(String(call[1]!.body ?? "null")) : undefined;
}

describe("ChatSetupPage", () => {
  it("renders the channel, test message and app status", async () => {
    mockFetch(userBootstrap(), (url, init) => (url === BASE && init.method === "GET" ? jsonResponse(chatSetupFixture()) : undefined));
    renderApp("/manager/standups/7/chat_setup");

    expect(await screen.findByRole("heading", { name: "Summary channel" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Slack · Daily standup · Standup Bot"));
    expect(screen.getByRole("link", { name: "Slack" })).toHaveAttribute("aria-current", "page");
    expect(screen.getAllByText("#standup (C0123)")).toHaveLength(2);
    expect(screen.getByLabelText("Channel ID")).toHaveValue("C0123");
    expect(screen.getByLabelText("Channel ID")).toHaveAttribute("placeholder", "Channel ID, like C0123");
    expect(screen.getByLabelText("Search channels")).toHaveAttribute("placeholder", "Search channels by name or ID");
    expect(screen.getByRole("link", { name: "Manage participants" })).toHaveAttribute("href", "/manager/standups/7/participants");
    expect(screen.queryByLabelText("Add a person")).toBeNull();

    expect(screen.getByRole("heading", { name: "Slack app status" })).toBeInTheDocument();
    expect(screen.getByText("The Slack app is installed.")).toBeInTheDocument();
    const credentials = screen.getByRole("list", { name: "Slack credentials" });
    expect(within(credentials).getByText("Bot token").closest("li")).toHaveTextContent("Configured");
    expect(within(credentials).getByText("Signing secret").closest("li")).toHaveTextContent("Missing");
    expect(within(credentials).getByText("(optional)")).toBeInTheDocument();
    expect(screen.getByText("Slack API authentication succeeded.")).toBeInTheDocument();
    expect(screen.getByText("Acme")).toBeInTheDocument();
  });

  it("works for Teams with its own copy and labels", async () => {
    const payload = chatSetupFixture({
      standup: standupFixture({ platform: "teams", platform_label: "Microsoft Teams", platform_channel: "T1|19:abc@thread.tacv2", platform_channel_name: "Standups" }),
      platform: { key: "teams", label: "Microsoft Teams", icon: "people" },
      channel: { platform_channel: "T1|19:abc@thread.tacv2", platform_channel_name: "Standups", channel_reference: "Standups" },
      copy: {
        channel_id_placeholder: "TEAM_ID|19:…@thread.tacv2",
        channel_search_placeholder: "Search by team or channel name",
      },
      integration_status: chatStatusFixture({
        platform: "teams",
        label: "Microsoft Teams",
        title: "Microsoft Teams app status",
        configured: false,
        status_label: "Needs setup",
        status_tone: "warning",
        connection: connectionResult({ success: false, status: "error", message: "Microsoft Teams isn't configured.", action: "Set MICROSOFT_APP_ID.", metadata: null }),
      }),
    });
    mockFetch(userBootstrap(), (url) => (url === BASE ? jsonResponse(payload) : undefined));
    renderApp("/manager/standups/7/chat_setup");

    await waitFor(() => expect(document.title).toBe("Microsoft Teams · Daily standup · Standup Bot"));
    expect(screen.getByRole("link", { name: "Microsoft Teams" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByLabelText("Channel ID")).toHaveAttribute("placeholder", "TEAM_ID|19:…@thread.tacv2");
    expect(screen.getByText("Needs setup")).toBeInTheDocument();
    expect(screen.getByText("Microsoft Teams isn't configured.")).toBeInTheDocument();
    expect(screen.getByText("Next step: Set MICROSOFT_APP_ID.")).toBeInTheDocument();
  });

  it("searches channels via the URL and uses a result", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === `${BASE}/channel` && init.method === "PATCH") {
        return jsonResponse({ ...chatSetupFixture({ channel: { platform_channel: "C222", platform_channel_name: "eng-standup", channel_reference: "#eng-standup (C222)" } }), notice: "Slack channel updated." });
      }
      if (url === `${BASE}?channel_query=eng&discover=channels`) return jsonResponse(chatSetupFixture({ channel_query: "eng", channel_result: channelResult() }));
      if (url === BASE) return jsonResponse(chatSetupFixture());
      return undefined;
    });
    const { router } = renderApp("/manager/standups/7/chat_setup");

    await user.type(await screen.findByLabelText("Search channels"), "eng");
    await user.click(screen.getByRole("button", { name: "Find channels" }));

    await waitFor(() => expect(router.state.location.search).toBe("?discover=channels&channel_query=eng"));
    const results = await screen.findByRole("list", { name: "Channel results" });
    expect(within(results).getByText("C222 · private")).toBeInTheDocument();

    await user.click(within(results).getByRole("button", { name: "Use channel eng-standup" }));

    expect(await screen.findByText("Slack channel updated.")).toBeInTheDocument();
    expect(requestBody(fetchMock, "PATCH", `${BASE}/channel`)).toEqual({ channel_id: "C222", channel_name: "eng-standup" });
    await waitFor(() => expect(screen.queryByRole("list", { name: "Channel results" })).toBeNull());
    expect(screen.getAllByText("#eng-standup (C222)").length).toBeGreaterThan(0);
  });

  it("saves a channel ID and shows its field error", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === `${BASE}/channel` && init.method === "PATCH") {
        return jsonResponse({ error: "Select a Slack channel or enter a channel ID.", errors: ["Select a Slack channel or enter a channel ID."], field_errors: { channel_id: ["Select a Slack channel or enter a channel ID."] } }, 422);
      }
      if (url === BASE) return jsonResponse(chatSetupFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/chat_setup");

    await user.clear(await screen.findByLabelText("Channel ID"));
    await user.click(screen.getByRole("button", { name: "Save channel" }));

    expect(await screen.findByText("Select a Slack channel or enter a channel ID.")).toBeInTheDocument();
    expect(screen.getByLabelText("Channel ID")).toHaveAttribute("aria-invalid", "true");
    expect(requestBody(fetchMock, "PATCH", `${BASE}/channel`)).toEqual({ channel_id: "" });
  });

  it("sends a test message and explains a failure", async () => {
    const user = userEvent.setup();
    let fail = false;
    mockFetch(userBootstrap(), (url, init) => {
      if (url === `${BASE}/test_message` && init.method === "POST") {
        if (fail) {
          return jsonResponse(
            { error: "not_in_channel", errors: ["not_in_channel"], test_message: connectionResult({ success: false, status: "error", message: "The bot isn't in #standup.", action: "Invite the bot to the channel.", metadata: null }) },
            422,
          );
        }
        return jsonResponse({ ...chatSetupFixture(), test_message: connectionResult({ message: "Posted." }), notice: "Test standup message sent." });
      }
      if (url === BASE) return jsonResponse(chatSetupFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/chat_setup");

    await user.click(await screen.findByRole("button", { name: "Send test message" }));
    expect(await screen.findByText("Test standup message sent.")).toBeInTheDocument();

    fail = true;
    await user.click(screen.getByRole("button", { name: "Send test message" }));
    expect(await screen.findByText("The bot isn't in #standup.")).toBeInTheDocument();
    expect(screen.getByText("Next step: Invite the bot to the channel.")).toBeInTheDocument();
  });

  it("shows a failed discovery", async () => {
    mockFetch(userBootstrap(), (url) =>
      url === `${BASE}?discover=channels`
        ? jsonResponse(chatSetupFixture({ channel_result: channelResult({ success: false, status: "error", records: null, message: "missing_scope", action: "Add the channels:read scope." }) }))
        : undefined,
    );
    renderApp("/manager/standups/7/chat_setup?discover=channels");

    expect(await screen.findByText("missing_scope")).toBeInTheDocument();
    expect(screen.getByText("Next step: Add the channels:read scope.")).toBeInTheDocument();
  });

  it("says when nothing matched", async () => {
    mockFetch(userBootstrap(), (url) => (url === `${BASE}?channel_query=zzz` ? jsonResponse(chatSetupFixture({ channel_query: "zzz", channel_result: channelResult({ records: [] }) })) : undefined));
    renderApp("/manager/standups/7/chat_setup?channel_query=zzz");

    expect(await screen.findByText("No channels matched.")).toBeInTheDocument();
    expect(screen.getByLabelText("Search channels")).toHaveValue("zzz");
  });
});
