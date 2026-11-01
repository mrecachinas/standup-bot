import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, teamsPlatform, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { editFormFixture, standupFixture, standupOverviewFixture } from "./standups/testFixtures";

type FetchMock = ReturnType<typeof mockFetch>;

function bodiesFor(fetchMock: FetchMock, url: string, method: string) {
  return fetchMock.mock.calls
    .filter(([requestUrl, init]) => String(requestUrl) === url && init?.method === method)
    .map(([, init]) => JSON.parse(String(init!.body)));
}

function setup(handler?: Parameters<typeof mockFetch>[1], payload = editFormFixture()) {
  return mockFetch(userBootstrap(), async (url, init) => {
    const handled = await handler?.(url, init);
    if (handled) return handled;
    if (url === "/api/standups/7/edit") return jsonResponse(payload);
    if (url === "/api/standups/7?include=overview") return jsonResponse(standupOverviewFixture());
    if (url === "/api/standups/preview") return jsonResponse(payload.schedule_preview);
    return undefined;
  });
}

describe("EditStandupPage", () => {
  it("shows the settings tab with the standup's current values", async () => {
    setup();
    renderApp("/manager/standups/7/edit");

    expect(await screen.findByLabelText(/^Name/)).toHaveValue("Daily standup");
    expect(document.title).toBe("Settings · Daily standup · Standup Bot");
    const tabs = screen.getByRole("navigation", { name: "Daily standup sections" });
    expect(within(tabs).getByRole("link", { name: "Settings" })).toHaveAttribute("aria-current", "page");
    expect(screen.queryByRole("link", { name: "Edit standup" })).toBeNull();
    expect(screen.queryByRole("navigation", { name: "Templates" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Slack" })).toBeNull();

    expect(screen.getByLabelText(/Post summaries to/)).toHaveValue("eng-standup");
    expect(screen.getAllByRole("textbox", { name: /^Question \d$/ })).toHaveLength(3);
    const chips = screen.getByRole("list", { name: "People in this standup" });
    expect(within(chips).getByText("Ada Lovelace")).toBeInTheDocument();
    expect(within(chips).getByText("inactive")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Participants" })).toHaveAttribute("href", "/manager/standups/7/participants");
    expect(screen.getByRole("link", { name: "Cancel" })).toHaveAttribute("href", "/manager/standups/7");

    await userEvent.setup().click(screen.getByText("Advanced settings"));
    expect(screen.getByRole("checkbox", { name: "Remind people who haven't answered after" })).toBeChecked();
    expect(screen.getByRole("spinbutton", { name: "Minutes before the first reminder" })).toHaveValue(60);
    expect(screen.getByRole("spinbutton", { name: "Maximum reminders" })).toHaveValue(2);
    expect(screen.getByLabelText("Greeting")).toHaveValue("Morning!");
    expect(screen.getByLabelText("Sign-off")).toHaveValue("Thanks!");
    expect(screen.getByRole("radio", { name: "Every week" })).toBeChecked();
  });

  it("saves changes, removing a person, then opens the standup", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7" && init.method === "PATCH" ? jsonResponse({ standup: standupFixture({ name: "Team daily" }), notice: "Team daily was updated." }) : undefined,
    );
    const { router } = renderApp("/manager/standups/7/edit");

    const name = await screen.findByLabelText(/^Name/);
    await user.clear(name);
    await user.type(name, "Team daily");
    await user.click(within(screen.getByRole("list", { name: "People in this standup" })).getByRole("button", { name: "Remove Ada Lovelace" }));
    await user.click(screen.getByText("Advanced settings"));
    await user.clear(screen.getByRole("spinbutton", { name: "Maximum reminders" }));
    await user.type(screen.getByRole("spinbutton", { name: "Maximum reminders" }), "3");
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/standups/7"));
    expect(await screen.findByText("Team daily was updated.")).toBeInTheDocument();
    const [body] = bodiesFor(fetchMock, "/api/standups/7", "PATCH");
    expect(body.standup).not.toHaveProperty("platform");
    expect(body.standup).not.toHaveProperty("platform_channel_name");
    expect(body.standup).toMatchObject({
      name: "Team daily",
      platform_channel: "eng-standup",
      max_reminders: "3",
      question_rows: ["What did you do yesterday?", "What will you do today?", ""],
      participant_handles: "",
    });
    expect(body.standup.participants).toEqual([
      { id: 1, platform_user_id: "U1", original_platform_user_id: "U1", display_name: "Ada Lovelace", cached_timezone: "Europe/London", active: true, _destroy: true },
      { id: 2, platform_user_id: "U2", original_platform_user_id: "U2", display_name: "Grace Hopper", cached_timezone: "", active: false, _destroy: false },
    ]);
  });

  it("picks a Teams channel and keeps its name", async () => {
    const user = userEvent.setup();
    const payload = editFormFixture({
      standup: standupFixture({ platform: "teams", platform_label: "Microsoft Teams", platform_channel: "T1|19:a@thread.tacv2", platform_channel_name: "Engineering › Standup" }),
      platform: teamsPlatform,
      channel: {
        input: "select",
        value: "T1|19:a@thread.tacv2",
        name: "Engineering › Standup",
        choices: [
          { id: "T1|19:a@thread.tacv2", label: "Engineering › Standup" },
          { id: "T1|19:b@thread.tacv2", label: "Engineering › General" },
        ],
        placeholder: "Pick a Teams channel",
        hint: null,
      },
    });
    const fetchMock = setup(
      (url, init) => (url === "/api/standups/7" && init.method === "PATCH" ? jsonResponse({ standup: payload.standup, notice: "Daily standup was updated." }) : undefined),
      payload,
    );
    renderApp("/manager/standups/7/edit");

    const select = await screen.findByLabelText(/Post summaries to/);
    expect(select).toHaveValue("T1|19:a@thread.tacv2");
    await user.selectOptions(select, "T1|19:b@thread.tacv2");
    await user.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(bodiesFor(fetchMock, "/api/standups/7", "PATCH")).toHaveLength(1));
    const [body] = bodiesFor(fetchMock, "/api/standups/7", "PATCH");
    expect(body.standup).toMatchObject({ platform_channel: "T1|19:b@thread.tacv2", platform_channel_name: "Engineering › General" });
  });

  it("asks before leaving with unsaved changes", async () => {
    const user = userEvent.setup();
    setup();
    const { router } = renderApp("/manager/standups/7/edit");

    await user.type(await screen.findByLabelText(/^Name/), "!");
    await user.click(screen.getByRole("link", { name: "Cancel" }));
    const dialog = await screen.findByRole("alertdialog", { name: "Leave without saving?" });
    await user.click(within(dialog).getByRole("button", { name: "Stay" }));
    expect(router.state.location.pathname).toBe("/manager/standups/7/edit");
    expect(screen.getByLabelText(/^Name/)).toHaveValue("Daily standup!");

    await user.click(screen.getByRole("link", { name: "Cancel" }));
    await user.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Leave" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/standups/7"));
  });

  it("pauses the standup from the header", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/pause" && init.method === "PATCH" ? jsonResponse({ standup: standupFixture({ active: false }), notice: "Daily standup was paused." }) : undefined,
    );
    renderApp("/manager/standups/7/edit");

    await user.click(await screen.findByRole("button", { name: "Pause Daily standup" }));
    expect(await screen.findByText("Daily standup was paused.")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Resume Daily standup" })).toBeInTheDocument();
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === "PATCH").map(([url]) => url)).toEqual(["/api/standups/7/pause"]);
  });

  it("says when the standup can't be edited", async () => {
    setup((url) => (url === "/api/standups/9/edit" ? jsonResponse({ error: "Forbidden" }, 403) : undefined));
    renderApp("/manager/standups/9/edit");

    expect(await screen.findByRole("heading", { name: "You don't manage this standup" })).toBeInTheDocument();
  });
});
