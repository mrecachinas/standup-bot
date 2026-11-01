import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, memberBootstrap, signedOutBootstrap, userBootstrap } from "../test/fixtures";
import { mockFetch, renderApp } from "../test/render";

describe("AppShell navigation", () => {
  it("shows only the member pages to a member", async () => {
    mockFetch(memberBootstrap());
    renderApp("/me");

    const me = await screen.findByRole("navigation", { name: "Me" });
    expect(within(me).getByRole("link", { name: "My standups" })).toHaveAttribute("aria-current", "page");
    expect(within(me).getByRole("link", { name: "My responses" })).toHaveAttribute("href", "/me/responses");
    expect(within(me).getByRole("link", { name: "Availability" })).toHaveAttribute("href", "/me/availability");
    expect(screen.queryByRole("navigation", { name: "Main" })).toBeNull();
    expect(screen.queryByRole("link", { name: "New standup" })).toBeNull();
    expect(screen.getByText("Sam Member")).toBeInTheDocument();
    expect(screen.getByText("Member")).toBeInTheDocument();
  });

  it("shows manager pages and the standups list to a user", async () => {
    mockFetch(userBootstrap());
    renderApp("/manager/standups/7/participants");

    const main = await screen.findByRole("navigation", { name: "Main" });
    expect(within(main).getByRole("link", { name: "Overview" })).toHaveAttribute("href", "/manager/standups");
    expect(within(main).getByRole("link", { name: "Integrations" })).toBeInTheDocument();
    expect(within(main).queryByRole("link", { name: "Admin" })).toBeNull();
    expect(screen.queryByRole("navigation", { name: "Me" })).toBeNull();

    const standups = screen.getByRole("navigation", { name: "Standups" });
    const daily = within(standups).getByRole("link", { name: /Daily standup/ });
    expect(daily).toHaveAttribute("href", "/manager/standups/7");
    expect(daily).toHaveAttribute("aria-current", "page");
    expect(within(standups).getByRole("img", { name: "Paused" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "New standup" })).toHaveAttribute("href", "/manager/standups/new");
    expect(screen.getByText("Maya Manager")).toBeInTheDocument();
  });

  it("adds the Admin link for admins", async () => {
    mockFetch(userBootstrap({ admin: true }));
    renderApp("/admin");

    const main = await screen.findByRole("navigation", { name: "Main" });
    expect(within(main).getByRole("link", { name: "Admin" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByText("Admin", { selector: "div" })).toBeInTheDocument();
    expect(document.title).toBe("Admin · Standup Bot");
  });

  it("shows both sections to a user who is also a member", async () => {
    mockFetch(userBootstrap({ member: memberBootstrap().member }));
    renderApp("/manager/standups");

    expect(await screen.findByRole("navigation", { name: "Me" })).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "Main" })).toBeInTheDocument();
    expect(screen.getByText("You")).toBeInTheDocument();
  });

  it("hides /admin from non-admins", async () => {
    mockFetch(userBootstrap());
    renderApp("/admin");
    expect(await screen.findByRole("heading", { name: "Page not found" })).toBeInTheDocument();
  });

  it("sends signed-out visitors to sign in, keeping the page in ?next", async () => {
    mockFetch(signedOutBootstrap());
    const { router } = renderApp("/manager/standups/7");

    await waitFor(() => expect(router.state.location.pathname).toBe("/session/new"));
    expect(router.state.location.search).toBe("?next=%2Fmanager%2Fstandups%2F7");
  });

  it("routes / by identity", async () => {
    mockFetch(memberBootstrap());
    const { router } = renderApp("/");
    await waitFor(() => expect(router.state.location.pathname).toBe("/me"));
  });

  it("signs out", async () => {
    const user = userEvent.setup();
    mockFetch(userBootstrap(), (url, init) => (url === "/api/session" && init.method === "DELETE" ? jsonResponse(signedOutBootstrap()) : undefined));
    const { router } = renderApp("/manager/standups");

    await user.click(await screen.findByRole("button", { name: "Sign out" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/session/new"));
    expect(await screen.findByRole("link", { name: "Sign in with Slack" })).toBeInTheDocument();
  });

  it("shows the bootstrap flash as a toast", async () => {
    mockFetch(userBootstrap({ flash: [{ type: "danger", message: "Slack sign-in failed." }] }));
    renderApp("/manager/standups");

    expect(await screen.findByText("Slack sign-in failed.")).toBeInTheDocument();
  });
});
