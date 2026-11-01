import { crc32 } from "node:zlib";
import { expect, test } from "@playwright/test";
import { ADMIN, ADMIN_STATE, MANAGER, MANAGER_STATE, signIn, uniqueName, watchForErrors } from "./support";

test.describe("signing in", () => {
  test("signs in with an access token and signs out", async ({ page }) => {
    const checkErrors = watchForErrors(page);

    await page.goto("/manager/standups");
    await expect(page).toHaveURL(/\/session\/new\?next=/);

    await signIn(page, MANAGER);
    await expect(page.getByRole("heading", { level: 1, name: "Overview" })).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Standups" }).getByRole("link", { name: "Daily Standup" })).toBeVisible();
    // A manager only sees the standups they manage.
    await expect(page.getByRole("navigation", { name: "Standups" }).getByRole("link", { name: "Weekly Planning" })).toHaveCount(0);

    await page.getByRole("button", { name: "Sign out" }).click();
    await expect(page).toHaveURL(/\/session\/new/);
    await page.goto("/manager/standups");
    await expect(page).toHaveURL(/\/session\/new/);

    checkErrors();
  });

  test("rejects a wrong access token", async ({ page }) => {
    await page.goto("/session/new");
    await page.getByRole("textbox", { name: "Email" }).fill(ADMIN.email);
    await page.getByRole("textbox", { name: "Access token" }).fill("not-the-token");
    await page.getByRole("button", { name: "Sign in" }).click();

    await expect(page.getByText("That email and access token don't match an active account.")).toBeVisible();
    await expect(page).toHaveURL(/\/session\/new/);
  });
});

test.describe("as a standup manager", () => {
  test.use({ storageState: MANAGER_STATE });

  test("creates, pauses, resumes, and edits a standup", async ({ page }, testInfo) => {
    const checkErrors = watchForErrors(page);
    const name = uniqueName(testInfo, "E2E standup");
    const renamed = `${name} (renamed)`;

    await page.goto("/manager/standups");
    await page.getByRole("link", { name: "New standup" }).first().click();
    await expect(page.getByRole("heading", { level: 1, name: "Create a standup" })).toBeVisible();

    await page.getByRole("textbox", { name: "Name" }).fill(name);
    await page.getByRole("textbox", { name: "Post summaries to" }).fill("e2e-standup");
    await page.getByRole("button", { name: "Create standup" }).click();

    await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
    await expect(page.getByText(`${name} was created.`)).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Standups" }).getByRole("link", { name })).toBeVisible();

    await page.getByRole("button", { name: `Pause ${name}` }).click();
    await expect(page.getByText(`${name} was paused.`)).toBeVisible();
    await page.getByRole("button", { name: `Resume ${name}` }).click();
    await expect(page.getByText(`${name} was resumed.`)).toBeVisible();

    await page.getByRole("navigation", { name: `${name} sections` }).getByRole("link", { name: "Settings" }).click();
    await page.getByRole("textbox", { name: "Name" }).fill(renamed);
    await page.getByRole("button", { name: "Save changes" }).click();

    await expect(page.getByRole("heading", { level: 1, name: renamed })).toBeVisible();
    await expect(page.getByText(`${renamed} was updated.`)).toBeVisible();

    checkErrors();
  });

  test("only asks before leaving the standup form when something changed", async ({ page }) => {
    const dialogs: string[] = [];
    page.on("dialog", async (dialog) => {
      dialogs.push(dialog.type());
      await dialog.accept();
    });

    await page.goto("/manager/standups/new");
    await expect(page.getByRole("heading", { level: 1, name: "Create a standup" })).toBeVisible();
    await page.getByRole("link", { name: "Overview" }).click();
    await expect(page).toHaveURL(/\/manager\/standups$/);
    await page.goto("/manager/standups/new");
    await expect(page.getByRole("heading", { level: 1, name: "Create a standup" })).toBeVisible();
    await page.goto("/manager/standups");
    expect(dialogs).toEqual([]);

    await page.goto("/manager/standups/new");
    await page.getByRole("textbox", { name: "Name" }).fill("Half-finished");
    await page.getByRole("link", { name: "Overview" }).click();
    await expect(page.getByRole("alertdialog").or(page.getByRole("dialog"))).toBeVisible();
  });

  test("shows validation errors on the standup form", async ({ page }) => {
    await page.goto("/manager/standups/new");
    await page.getByRole("textbox", { name: "Post summaries to" }).fill("e2e-standup");
    await page.getByRole("button", { name: "Create standup" }).click();

    await expect(page.getByText(/Name can't be blank/i).first()).toBeVisible();
    await expect(page).toHaveURL(/\/manager\/standups\/new/);
  });

  test("imports participants into a standup", async ({ page }, testInfo) => {
    const checkErrors = watchForErrors(page);
    const name = uniqueName(testInfo, "E2E roster");

    await page.goto("/manager/standups/new");
    await page.getByRole("textbox", { name: "Name" }).fill(name);
    await page.getByRole("textbox", { name: "Post summaries to" }).fill("e2e-roster");
    await page.getByRole("button", { name: "Create standup" }).click();
    await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();

    await page.getByRole("navigation", { name: `${name} sections` }).getByRole("link", { name: /Participants/ }).click();
    await page.getByText("Import a list").click();
    await page.getByRole("textbox", { name: "Participants" }).fill("U0E2E0001,Erin Example,Europe/London,true");
    await page.getByRole("button", { name: "Import participants" }).click();

    await expect(page.getByText("Erin Example").first()).toBeVisible();

    checkErrors();
  });

  test("opens every tab of a standup", async ({ page }) => {
    const checkErrors = watchForErrors(page);
    await page.goto("/manager/standups");
    await page.getByRole("navigation", { name: "Standups" }).getByRole("link", { name: "Daily Standup" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Daily Standup" })).toBeVisible();

    const tabs = page.getByRole("navigation", { name: "Daily Standup sections" });
    for (const [tab, path] of [
      ["Insights", /\/analytics/],
      ["Responses", /\/responses/],
      [/Participants/, /\/participants/],
      ["Schedule", /\/schedule_exceptions/],
      ["Reports", /\/report/],
      ["Slack", /\/chat_setup/],
      ["Settings", /\/edit/],
      ["Overview", /\/manager\/standups\/\d+$/],
    ] as const) {
      await tabs.getByRole("link", { name: tab }).click();
      await expect(page).toHaveURL(path);
      await expect(tabs.getByRole("link", { name: tab })).toHaveAttribute("aria-current", "page");
      await expect(page.getByRole("heading", { name: "Something went wrong" })).toHaveCount(0);
    }

    checkErrors();
  });

  test("a manager can't open someone else's standup or the admin page", async ({ page }) => {
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();

    // Weekly Planning belongs to another manager (test/fixtures/standup_ownerships.yml).
    await page.goto(`/manager/standups/${fixtureId("weekly")}`);
    await expect(page.getByRole("heading", { name: "You don't manage this standup" })).toBeVisible();
    await page.goto(`/manager/standups/${fixtureId("weekly")}/participants`);
    await expect(page.getByText("Alice Johnson")).toHaveCount(0);
  });
});

test.describe("as an admin", () => {
  test.use({ storageState: ADMIN_STATE });

  test("admins see integrations and the admin dashboard", async ({ page }) => {
    const checkErrors = watchForErrors(page);
    await page.goto("/manager/standups");

    await page.getByRole("link", { name: "Integrations" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Integrations" })).toBeVisible();

    await page.getByRole("link", { name: "Admin" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Admin" })).toBeVisible();
    await expect(page.getByText("Admin User").first()).toBeVisible();

    checkErrors();
  });
});

/** The id Rails gives a fixture row (ActiveRecord::FixtureSet.identify). */
function fixtureId(label: string) {
  return crc32(label) % (2 ** 30 - 1);
}
