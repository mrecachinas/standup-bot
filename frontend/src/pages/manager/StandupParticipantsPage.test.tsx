import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { participantsConsole, rosterParticipant, standupFixture } from "./roster/testFixtures";

const PAGE = "/manager/standups/7/participants";
const INDEX = "/api/standups/7/participants?view=console";

type FetchMock = ReturnType<typeof mockFetch>;

function callsTo(fetchMock: FetchMock, method: string, url: string) {
  return fetchMock.mock.calls.filter(([callUrl, init]) => String(callUrl) === url && (init?.method ?? "GET") === method);
}

function bodyOf(fetchMock: FetchMock, method: string, url: string) {
  const call = callsTo(fetchMock, method, url).at(-1);
  return call ? JSON.parse(String(call[1]!.body ?? "null")) : undefined;
}

function setup(handler?: (url: string, init: RequestInit) => Response | undefined, payload = participantsConsole()) {
  return mockFetch(userBootstrap(), (url, init) => handler?.(url, init) ?? (url === INDEX && init.method === "GET" ? jsonResponse(payload) : undefined));
}

async function openRowMenu(user: ReturnType<typeof userEvent.setup>, name: string) {
  await user.click(await screen.findByRole("button", { name: `More actions for ${name}` }));
}

describe("StandupParticipantsPage", () => {
  it("shows the roster, managers, platform copy and summary", async () => {
    setup();
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "Add people" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Participants · Daily standup · Standup Bot"));
    expect(screen.getByRole("link", { name: /Participants/ })).toHaveAttribute("aria-current", "page");

    const input = screen.getByLabelText("Slack user");
    expect(input).toHaveAttribute("placeholder", "@jane, Jane Doe, or U123ABC");
    expect(screen.getByText(/Use a Slack @username, display name, mention, or user ID/)).toBeInTheDocument();
    expect(screen.getByText("Sync from a Slack channel")).toBeInTheDocument();

    const managers = screen.getByRole("list", { name: "Managers" });
    expect(within(managers).getByText("Maya Manager")).toBeInTheDocument();
    expect(within(managers).getByText("(you)")).toBeInTheDocument();
    expect(within(managers).queryByRole("button", { name: /Remove|Stop managing/ })).toBeNull();
    expect(screen.getByText("Make someone else a manager from the list below before you can step down.")).toBeInTheDocument();

    expect(screen.getByText("2 participants · 1 active · 1 timezone needing sync")).toBeInTheDocument();
    const table = screen.getByRole("table", { name: "People" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(rows[1]).toHaveTextContent("John Doe");
    expect(rows[1]).toHaveTextContent("U123456");
    expect(rows[1]).toHaveTextContent("Active");
    expect(rows[1]).toHaveTextContent("Manager");
    expect(rows[1]).toHaveTextContent("America/New_York");
    expect(rows[1]).toHaveTextContent("Synced");
    expect(rows[2]).toHaveTextContent("Inactive");
    expect(rows[2]).toHaveTextContent("Unknown");
    expect(rows[2]).toHaveTextContent("Needs sync");
    expect(rows[2]).toHaveTextContent("Away through 2026-11-20");
  });

  it("shows the empty state and the admins-only manager note", async () => {
    setup(
      undefined,
      participantsConsole({
        participants: [],
        managers: [],
        summary: { participant_count: 0, active_count: 0, stale_timezone_count: 0, holiday_today: false },
      }),
    );
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "No participants yet" })).toBeInTheDocument();
    expect(screen.getByText("Add people above, or sync everyone from a Slack channel.")).toBeInTheDocument();
    expect(screen.getByText("Only admins manage this standup right now. Make someone a manager from the list below.")).toBeInTheDocument();
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("adds a person with lookup and reloads", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/participants" && init.method === "POST"
        ? jsonResponse({ participant: rosterParticipant({ id: 13, display_name: "Alice" }), notice: "Added Alice to Daily standup." }, 201)
        : undefined,
    );
    renderApp(PAGE);

    await user.type(await screen.findByLabelText("Slack user"), " @alice ");
    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByText("Added Alice to Daily standup.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", "/api/standups/7/participants")).toEqual({ participant: { platform_user_id: "@alice", active: true }, lookup: true });
    expect(screen.getByLabelText("Slack user")).toHaveValue("");
    await waitFor(() => expect(callsTo(fetchMock, "GET", INDEX)).toHaveLength(2));
  });

  it("shows field and base errors when adding fails", async () => {
    const user = userEvent.setup();
    setup((url, init) => {
      if (url !== "/api/standups/7/participants" || init.method !== "POST") return undefined;
      const body = JSON.parse(String(init.body));
      return body.participant.platform_user_id === "bad"
        ? jsonResponse({ errors: ["Platform user must be a Slack user ID"], field_errors: { platform_user_id: ["must be a Slack user ID"] } }, 422)
        : jsonResponse({ errors: ['No Slack user matched "@nobody".'], field_errors: { base: ['No Slack user matched "@nobody".'] } }, 422);
    });
    renderApp(PAGE);

    const input = await screen.findByLabelText("Slack user");
    await user.type(input, "bad");
    await user.click(screen.getByRole("button", { name: "Add" }));
    expect(await screen.findByText("Slack user must be a Slack user ID")).toBeInTheDocument();

    await user.clear(input);
    await user.type(input, "@nobody");
    await user.click(screen.getByRole("button", { name: "Add" }));
    expect(await screen.findByText('No Slack user matched "@nobody".')).toBeInTheDocument();
    expect(screen.getByText("1 error prevented saving this participant")).toBeInTheDocument();
    expect(screen.queryByText("Slack user must be a Slack user ID")).toBeNull();
  });

  it("edits a participant and shows 422 field errors in the dialog", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url, init) => {
      if (url !== "/api/standups/7/participants/12" || init.method !== "PATCH") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse({ errors: ["Cached timezone is not a valid timezone"], field_errors: { cached_timezone: ["is not a valid timezone"] } }, 422)
        : jsonResponse({ participant: rosterParticipant({ id: 12 }), notice: "Saved Janet Smith." });
    });
    renderApp(PAGE);

    await user.click(await screen.findByRole("button", { name: "Edit Jane Smith" }));
    const dialog = await screen.findByRole("dialog", { name: "Edit Jane Smith" });
    const name = within(dialog).getByLabelText(/Name/);
    expect(name).toHaveValue("Jane Smith");
    await user.clear(name);
    await user.type(name, "Janet Smith");
    await user.type(within(dialog).getByLabelText("Timezone"), "Mars/Base");
    await user.clear(within(dialog).getByLabelText("Away until"));
    await user.click(within(dialog).getByLabelText("Active"));
    await user.click(within(dialog).getByRole("button", { name: "Save" }));

    expect(await within(dialog).findByText("Timezone is not a valid timezone")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "PATCH", "/api/standups/7/participants/12")).toEqual({
      participant: { display_name: "Janet Smith", cached_timezone: "Mars/Base", vacation_until: null, active: true },
    });

    const timezone = within(dialog).getByLabelText("Timezone");
    await user.clear(timezone);
    await user.type(timezone, "Europe/London");
    await user.click(within(dialog).getByRole("button", { name: "Save" }));

    expect(await screen.findByText("Saved Janet Smith.")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(bodyOf(fetchMock, "PATCH", "/api/standups/7/participants/12").participant.cached_timezone).toBe("Europe/London");
  });

  it("toggles a participant's active flag from the row menu", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/participants/11" && init.method === "PATCH"
        ? jsonResponse({ participant: rosterParticipant({ active: false }), notice: "Saved John Doe." })
        : undefined,
    );
    renderApp(PAGE);

    await openRowMenu(user, "John Doe");
    await user.click(screen.getByRole("menuitem", { name: "Mark inactive" }));

    expect(await screen.findByText("Saved John Doe.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "PATCH", "/api/standups/7/participants/11")).toEqual({ participant: { active: false } });
  });

  it("removes a participant after confirming", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/participants/12" && init.method === "DELETE" ? new Response(null, { status: 204 }) : undefined,
    );
    renderApp(PAGE);

    await openRowMenu(user, "Jane Smith");
    await user.click(screen.getByRole("menuitem", { name: "Remove from standup" }));
    const dialog = await screen.findByRole("alertdialog", { name: "Remove Jane Smith?" });
    expect(dialog).toHaveTextContent("Remove Jane Smith from Daily standup?");
    await user.click(within(dialog).getByRole("button", { name: "Remove" }));

    expect(await screen.findByText("Removed Jane Smith from Daily standup.")).toBeInTheDocument();
    expect(callsTo(fetchMock, "DELETE", "/api/standups/7/participants/12")).toHaveLength(1);
    await waitFor(() => expect(callsTo(fetchMock, "GET", INDEX)).toHaveLength(2));
  });

  it("makes someone a manager and shows a 422 from the server", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url, init) => {
      if (url !== "/api/standups/7/managers" || init.method !== "POST") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse({ errors: ["Jane Smith's account is turned off, so they can't manage standups."] }, 422)
        : jsonResponse({ manager: {}, participant_id: 12, can_manage: true, notice: "Jane Smith can now manage Daily standup." }, 201);
    });
    renderApp(PAGE);

    await openRowMenu(user, "Jane Smith");
    await user.click(screen.getByRole("menuitem", { name: "Make manager" }));
    let dialog = await screen.findByRole("alertdialog", { name: "Make Jane Smith a manager?" });
    expect(dialog).toHaveTextContent("Let Jane Smith manage Daily standup? They'll be able to change its settings, people, and schedule.");
    await user.click(within(dialog).getByRole("button", { name: "Make manager" }));
    expect(await screen.findByText("Jane Smith's account is turned off, so they can't manage standups.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", "/api/standups/7/managers")).toEqual({ participant_id: 12 });

    await openRowMenu(user, "Jane Smith");
    await user.click(screen.getByRole("menuitem", { name: "Make manager" }));
    dialog = await screen.findByRole("alertdialog");
    await user.click(within(dialog).getByRole("button", { name: "Make manager" }));
    expect(await screen.findByText("Jane Smith can now manage Daily standup.")).toBeInTheDocument();
    expect(screen.queryByText("Jane Smith's account is turned off, so they can't manage standups.")).toBeNull();
  });

  it("leaves for the standups list after removing yourself as a manager", async () => {
    const user = userEvent.setup();
    const payload = participantsConsole({
      managers: [
        {
          id: 1,
          name: "Maya Manager",
          avatar_url: null,
          admin: false,
          role_label: "Manager",
          platform_user_id: "U123456",
          current_user: true,
          can_remove: true,
        },
        { id: 2, name: "Omar Owner", avatar_url: null, admin: true, role_label: "Admin", platform_user_id: null, current_user: false, can_remove: true },
      ],
      manager_rules: { minimum_managers: 1, can_remove_managers: true, only_admins_manage: false },
    });
    let sessionCalls = 0;
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === INDEX) return jsonResponse(payload);
      if (url === "/api/standups/7/managers/1" && init.method === "DELETE")
        return jsonResponse({ can_manage: false, user_id: 1, notice: "You no longer manage Daily standup." });
      if (url === "/api/session") sessionCalls += 1;
      return undefined;
    });
    const { router } = renderApp(PAGE);

    const managers = await screen.findByRole("list", { name: "Managers" });
    expect(within(managers).getByText("Admin")).toBeInTheDocument();
    await user.click(within(managers).getByRole("button", { name: "Stop managing Daily standup" }));
    const dialog = await screen.findByRole("alertdialog", { name: "Stop managing Daily standup?" });
    expect(dialog).toHaveTextContent("You'll lose access to it.");
    await user.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/standups"));
    expect(await screen.findByText("You no longer manage Daily standup.")).toBeInTheDocument();
    expect(callsTo(fetchMock, "DELETE", "/api/standups/7/managers/1")).toHaveLength(1);
    expect(sessionCalls).toBeGreaterThanOrEqual(2);
  });

  it("imports a list and shows import errors", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    const fetchMock = setup((url) => {
      if (url !== "/api/standups/7/participants/bulk_import") return undefined;
      attempts += 1;
      return attempts === 1
        ? jsonResponse(
            {
              errors: ['Line 2: No Slack user matched "@ghost".'],
              summary: { created_count: 1, updated_count: 0, unchanged_count: 0, deactivated_count: 0, error_count: 1 },
            },
            422,
          )
        : jsonResponse({
            notice: "Import finished: 2 added, 0 updated, 0 unchanged.",
            summary: { created_count: 2, updated_count: 0, unchanged_count: 0, deactivated_count: 0, error_count: 0 },
            errors: [],
          });
    });
    renderApp(PAGE);

    await user.click(await screen.findByText("Import a list"));
    const textarea = screen.getByLabelText("Participants");
    expect(textarea).toHaveAttribute("placeholder", "@alice\n<@U456|Bob>\nU789,Carol,Europe/London,true");
    expect(screen.getByText("Slack username, mention, or ID. Optional extra columns: name, timezone, active.")).toBeInTheDocument();
    await user.type(textarea, "@alice{enter}@ghost");
    await user.click(screen.getByRole("button", { name: "Import participants" }));

    expect(await screen.findByText("Import needs attention")).toBeInTheDocument();
    expect(screen.getByText('Line 2: No Slack user matched "@ghost".')).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", "/api/standups/7/participants/bulk_import")).toEqual({ participants_text: "@alice\n@ghost" });
    // One row was still added, so the roster reloads.
    await waitFor(() => expect(callsTo(fetchMock, "GET", INDEX)).toHaveLength(2));
    expect(textarea).toHaveValue("@alice\n@ghost");

    await user.click(screen.getByRole("button", { name: "Import participants" }));
    expect(await screen.findByText("Import finished: 2 added, 0 updated, 0 unchanged.")).toBeInTheDocument();
    expect(screen.queryByText("Import needs attention")).toBeNull();
    expect(screen.getByLabelText("Participants")).toHaveValue("");
  });

  it("syncs from a channel", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url) =>
      url === "/api/standups/7/participants/sync"
        ? jsonResponse({ notice: "Synced Slack channel: 1 added, 2 updated, 0 unchanged, 1 marked inactive.", summary: null, errors: [] })
        : undefined,
    );
    renderApp(PAGE);

    await user.click(await screen.findByText("Sync from a Slack channel"));
    const channel = screen.getByLabelText("Channel ID or name");
    expect(channel).toHaveValue("C0123");
    await user.clear(channel);
    await user.type(channel, "C0999");
    await user.click(screen.getByLabelText("Mark people who aren't in the channel as inactive"));
    await user.click(screen.getByRole("button", { name: "Sync channel" }));

    expect(await screen.findByText("Synced Slack channel: 1 added, 2 updated, 0 unchanged, 1 marked inactive.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "POST", "/api/standups/7/participants/sync")).toEqual({ channel: "C0999", deactivate_missing: true });
  });

  it("shows sync errors", async () => {
    const user = userEvent.setup();
    setup((url) =>
      url === "/api/standups/7/participants/sync"
        ? jsonResponse({ errors: ["You can only sync people from a channel you're in."], summary: null }, 422)
        : undefined,
    );
    renderApp(PAGE);

    await user.click(await screen.findByText("Sync from a Slack channel"));
    await user.click(screen.getByRole("button", { name: "Sync channel" }));
    expect(await screen.findByText("Slack sync needs attention")).toBeInTheDocument();
    expect(screen.getByText("You can only sync people from a channel you're in.")).toBeInTheDocument();
  });

  it("pauses the standup and refreshes the sidebar", async () => {
    const user = userEvent.setup();
    const fetchMock = setup((url, init) =>
      url === "/api/standups/7/pause" && init.method === "PATCH"
        ? jsonResponse({ standup: standupFixture({ active: false }), notice: "Paused Daily standup." })
        : undefined,
    );
    renderApp(PAGE);

    await user.click(await screen.findByRole("button", { name: "Pause Daily standup" }));
    expect(await screen.findByText("Paused Daily standup.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Resume Daily standup" })).toBeInTheDocument();
    expect(callsTo(fetchMock, "GET", "/api/session").length).toBeGreaterThanOrEqual(2);
  });

  it("explains a 403", async () => {
    mockFetch(userBootstrap(), (url) => (url === INDEX ? jsonResponse({ error: "You don't have access to that." }, 403) : undefined));
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "You don't manage this standup" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Back to standups" })).toHaveAttribute("href", "/manager/standups");
  });
});
