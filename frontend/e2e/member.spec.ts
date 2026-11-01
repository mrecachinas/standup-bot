import { expect, test, type Page } from "@playwright/test";
import { watchForErrors } from "./support";

/** "U123456" is John Doe in Daily Standup (test/fixtures/standup_participants.yml). */
const MEMBER_SLACK_ID = "U123456";

// script/e2e-server fakes Slack's token exchange. Rather than visit slack.com,
// start sign-in with the browser's cookies, read the state Rails put in the
// redirect, and come straight back to the real callback with that state.
async function signInWithSlack(page: Page, slackUserId: string, landsOn: RegExp) {
  await page.goto("/session/new");
  await expect(page.getByRole("link", { name: "Sign in with Slack" })).toHaveAttribute("href", "/auth/slack");

  const start = await page.request.get("/auth/slack", { maxRedirects: 0 });
  expect(start.status()).toBe(303);
  const authorize = new URL(start.headers().location);
  expect(authorize.host).toBe("slack.com");

  const callback = new URL(authorize.searchParams.get("redirect_uri")!);
  callback.searchParams.set("code", slackUserId);
  callback.searchParams.set("state", authorize.searchParams.get("state")!);
  await page.goto(callback.toString());
  await expect(page).toHaveURL(landsOn);
}

test("a member signs in with Slack and uses the member area", async ({ page }) => {
  const checkErrors = watchForErrors(page);
  await signInWithSlack(page, MEMBER_SLACK_ID, /\/me$/);

  await expect(page.getByRole("heading", { level: 1, name: "My standups" })).toBeVisible();
  await expect(page.getByText("Daily Standup").first()).toBeVisible();

  await page.getByRole("link", { name: "My responses" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "My responses" })).toBeVisible();

  await page.getByRole("link", { name: "Availability" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Availability" })).toBeVisible();

  const lastDayAway = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  await page.getByLabel("Last day away").fill(lastDayAway);
  await page.getByRole("checkbox", { name: "Daily Standup" }).check();
  await page.getByRole("button", { name: "Save" }).click();
  const away = page.getByRole("region", { name: "Currently away" });
  await expect(away.getByText("Daily Standup")).toBeVisible();

  await away.getByRole("button", { name: "I'm back" }).click();
  await expect(page.getByRole("region", { name: "Currently away" })).toHaveCount(0);

  checkErrors();
});

test("someone who isn't in any standup lands in the console instead", async ({ page }) => {
  await signInWithSlack(page, "U0NOTINANY", /\/manager\/standups$/);
  await expect(page.getByRole("heading", { level: 1, name: "Overview" })).toBeVisible();
});
