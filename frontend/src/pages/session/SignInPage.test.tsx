import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, signedOutBootstrap, slackPlatform, teamsPlatform, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";

describe("SignInPage", () => {
  it("shows a button per platform with sign-in enabled, primary first", async () => {
    mockFetch(signedOutBootstrap());
    renderApp("/session/new");

    const slack = await screen.findByRole("link", { name: "Sign in with Slack" });
    const microsoft = screen.getByRole("link", { name: "Sign in with Microsoft" });
    expect(slack).toHaveAttribute("href", "/auth/slack");
    expect(microsoft).toHaveAttribute("href", "/auth/microsoft");
    expect(slack).toHaveAttribute("data-variant", "primary");
    expect(microsoft).toHaveAttribute("data-variant", "default");
    expect(screen.getByText("Sign in with an access token instead")).toBeInTheDocument();
    expect(screen.getByText("Async standups for Slack and Microsoft Teams.")).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Sign in · Standup Bot"));
  });

  it("hides platforms without sign-in and shows the token form directly", async () => {
    mockFetch(signedOutBootstrap({ platforms: [{ ...slackPlatform, sign_in_enabled: false }, { ...teamsPlatform, sign_in_enabled: false }] }));
    renderApp("/session/new");

    expect(await screen.findByLabelText(/Email/)).toBeVisible();
    expect(screen.queryByRole("link", { name: /Sign in with/ })).toBeNull();
    expect(screen.queryByText("Sign in with an access token instead")).toBeNull();
  });

  it("only shows Microsoft when only Teams sign-in is configured", async () => {
    mockFetch(signedOutBootstrap({ platforms: [{ ...slackPlatform, sign_in_enabled: false }, teamsPlatform] }));
    renderApp("/session/new");

    expect(await screen.findByRole("link", { name: "Sign in with Microsoft" })).toHaveAttribute("data-variant", "primary");
    expect(screen.queryByRole("link", { name: "Sign in with Slack" })).toBeNull();
  });

  it("opens the token form with dev prefill", async () => {
    mockFetch(signedOutBootstrap({ dev_prefill: { email: "dev@example.com", access_token: "secret" } }));
    renderApp("/session/new");

    expect(await screen.findByLabelText(/Email/)).toHaveValue("dev@example.com");
    expect(screen.getByLabelText(/Access token/)).toHaveValue("secret");
    expect(screen.getByText("Sign in with an access token instead").closest("details")).toHaveAttribute("open");
  });

  it("signs in with a token and goes to ?next", async () => {
    const user = userEvent.setup();
    let signedIn = false;
    const fetchMock = mockFetch(signedOutBootstrap(), (url, init) => {
      if (url === "/api/session" && init.method === "POST") {
        signedIn = true;
        return jsonResponse(userBootstrap(), 201);
      }
      if (url === "/api/session" && signedIn) return jsonResponse(userBootstrap());
      return undefined;
    });
    const { router } = renderApp("/session/new?next=%2Fmanager%2Fintegrations");

    await user.click(await screen.findByText("Sign in with an access token instead"));
    await user.type(screen.getByLabelText(/Email/), "maya@example.com");
    await user.type(screen.getByLabelText(/Access token/), "token");
    await user.click(screen.getByRole("button", { name: "Sign in" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/integrations"));
    const post = fetchMock.mock.calls.find(([, init]) => init?.method === "POST")!;
    expect(JSON.parse(String(post[1]!.body))).toEqual({ email: "maya@example.com", access_token: "token" });
    expect((post[1]!.headers as Record<string, string>)["X-CSRF-Token"]).toBe("csrf-signed-out");
    expect(await screen.findByRole("heading", { name: "Integrations" })).toBeInTheDocument();
  });

  it("shows the error on a failed sign-in", async () => {
    const user = userEvent.setup();
    mockFetch(signedOutBootstrap({ dev_prefill: { email: "maya@example.com", access_token: "wrong" } }), (url, init) =>
      url === "/api/session" && init.method === "POST" ? jsonResponse({ error: "That email and access token don't match an active account." }, 401) : undefined,
    );
    const { router } = renderApp("/session/new");

    await user.click(await screen.findByRole("button", { name: "Sign in" }));

    expect(await screen.findByText("That email and access token don't match an active account.")).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/session/new");
    expect(screen.getByText("Sign in with an access token instead").closest("details")).toHaveAttribute("open");
  });

  it("redirects signed-in users home", async () => {
    mockFetch(userBootstrap());
    const { router } = renderApp("/session/new");

    await waitFor(() => expect(router.state.location.pathname).toBe("/manager/standups"));
  });
});
