import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { historyPayload } from "./roster/testFixtures";

const PAGE = "/manager/standups/7/responses";
const API = "/api/standups/7/responses?view=history";

type FetchMock = ReturnType<typeof mockFetch>;

function getUrls(fetchMock: FetchMock) {
  return fetchMock.mock.calls
    .filter(([url, init]) => String(url).startsWith("/api/standups/7/responses") && (init?.method ?? "GET") === "GET")
    .map(([url]) => String(url));
}

function setup(payload = historyPayload()) {
  return mockFetch(userBootstrap(), (url, init) => (url.startsWith("/api/standups/7/responses") && init.method === "GET" ? jsonResponse(payload) : undefined));
}

describe("StandupResponsesPage", () => {
  it("shows the summary, each day and each person's answers", async () => {
    setup();
    renderApp(PAGE);

    const day = await screen.findByRole("region", { name: "October 30, 2026" });
    await waitFor(() => expect(document.title).toBe("Responses · Daily standup · Standup Bot"));
    expect(screen.getByRole("link", { name: "Responses" })).toHaveAttribute("aria-current", "page");

    const summary = screen.getByRole("region", { name: "Summary" });
    expect(within(summary).getByText("Standup dates").parentElement).toHaveTextContent("1");
    expect(within(summary).getByText("Expected").parentElement).toHaveTextContent("2");
    expect(within(summary).getByText("50% of expected")).toBeInTheDocument();
    expect(within(summary).getByText("Missed").parentElement).toHaveTextContent("1");

    expect(within(day).getByText("1 answered · 1 missed · 2 expected")).toBeInTheDocument();
    expect(within(day).getByText("50%")).toBeInTheDocument();
    const [john, jane] = within(day).getAllByRole("listitem");
    expect(john).toHaveTextContent("John Doe");
    expect(john).toHaveTextContent("Answered");
    expect(within(john).getByText("What did you do yesterday?")).toBeInTheDocument();
    expect(within(john).getByText("Shipped the roster page")).toBeInTheDocument();
    expect(within(john).getByText("Answered at October 30, 2026 09:45")).toBeInTheDocument();
    expect(within(john).getByText("No answer provided.")).toBeInTheDocument();
    expect(john).toHaveTextContent("Submitted October 30, 2026 09:45 · Last updated October 30, 2026 10:15 · Updated after submission");
    expect(jane).toHaveTextContent("Missed");
    expect(within(jane).getByText("No response submitted for this standup date.")).toBeInTheDocument();
    expect(jane).not.toHaveTextContent("Submitted");

    expect(screen.getByLabelText("From")).toHaveValue("2026-10-19");
    expect(screen.getByLabelText("To")).toHaveValue("2026-11-01");
    expect(screen.getByLabelText("Person")).toHaveValue("");
    expect(screen.getByLabelText("Question")).toHaveValue("");
    expect(screen.getByRole("link", { name: "View insights" })).toHaveAttribute(
      "href",
      "/manager/standups/7/analytics?start_date=2026-10-19&end_date=2026-11-01",
    );
    expect(screen.getByRole("link", { name: "Reset filters" })).toHaveAttribute("href", "/manager/standups/7/responses");
    expect(screen.queryByText(/Showing the most recent/)).toBeNull();
  });

  it("shows the empty state and the range-limited notice", async () => {
    setup(
      historyPayload({ days: [], range_limited: true, summary: { dates: 0, expected: 0, answered: 0, missed: 0, answer_rate: null, answer_rate_tone: null } }),
    );
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "No runs in this range" })).toBeInTheDocument();
    expect(screen.getByText("Try a wider date range or clear the filters.")).toBeInTheDocument();
    expect(screen.getByText("Showing the most recent 90 days.")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "Summary" })).getByText("—")).toBeInTheDocument();
  });

  it("puts the filters in the URL and sends them to the API", async () => {
    const user = userEvent.setup();
    const fetchMock = setup();
    const { router } = renderApp(PAGE);

    const from = await screen.findByLabelText("From");
    await user.clear(from);
    await user.type(from, "2026-10-01");
    await user.selectOptions(screen.getByLabelText("Person"), "U234567");
    await user.selectOptions(screen.getByLabelText("Question"), "Any blockers?");
    await user.click(screen.getByRole("button", { name: "Apply" }));

    await waitFor(() => expect(router.state.location.search).toBe("?start_date=2026-10-01&end_date=2026-11-01&participant=U234567&question=Any+blockers%3F"));
    await waitFor(() => expect(getUrls(fetchMock)).toContain(`${API}&start_date=2026-10-01&end_date=2026-11-01&participant=U234567&question=Any+blockers%3F`));
    expect(getUrls(fetchMock)[0]).toBe(API);
  });

  it("loads a shared link's filters into the form", async () => {
    const fetchMock = setup(
      historyPayload({ filters: { start_date: "2026-10-01", end_date: "2026-10-15", participant: "U123456", question: "Any blockers?" } }),
    );
    renderApp(`${PAGE}?start_date=2026-10-01&end_date=2026-10-15&participant=U123456&question=Any+blockers%3F&utm=chat`);

    expect(await screen.findByLabelText("From")).toHaveValue("2026-10-01");
    expect(screen.getByLabelText("To")).toHaveValue("2026-10-15");
    expect(screen.getByLabelText("Person")).toHaveValue("U123456");
    expect(screen.getByLabelText("Question")).toHaveValue("Any blockers?");
    expect(getUrls(fetchMock)[0]).toBe(`${API}&start_date=2026-10-01&end_date=2026-10-15&participant=U123456&question=Any+blockers%3F`);
  });

  it("explains a 403", async () => {
    mockFetch(userBootstrap(), (url) =>
      url.startsWith("/api/standups/7/responses") ? jsonResponse({ error: "You don't have access to that." }, 403) : undefined,
    );
    renderApp(PAGE);

    expect(await screen.findByRole("heading", { name: "You don't manage this standup" })).toBeInTheDocument();
  });
});
