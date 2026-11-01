import { expect, type Page, type TestInfo } from "@playwright/test";

/** Fixture accounts from test/fixtures/users.yml. */
export const ADMIN = { email: "admin@example.com", token: "admin-access-token" };
export const MANAGER = { email: "manager@example.com", token: "manager-access-token" };

export const MANAGER_STATE = "e2e/.auth/manager.json";
export const ADMIN_STATE = "e2e/.auth/admin.json";

export async function signIn(page: Page, account: { email: string; token: string }) {
  await page.goto("/session/new");
  await page.getByRole("textbox", { name: "Email" }).fill(account.email);
  await page.getByRole("textbox", { name: "Access token" }).fill(account.token);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/manager\/standups$/);
}

/**
 * Fails the test on uncaught errors or console errors. Failed requests the
 * page handles itself (like a 404 it shows a message for) are allowed.
 */
export function watchForErrors(page: Page) {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error" && !message.text().startsWith("Failed to load resource")) errors.push(message.text());
  });
  return () => expect(errors, "console errors").toEqual([]);
}

export function uniqueName(testInfo: TestInfo, label: string) {
  return `${label} ${testInfo.project.name} ${Date.now().toString(36)}`;
}
