import { test as setup } from "@playwright/test";
import { ADMIN, ADMIN_STATE, MANAGER, MANAGER_STATE, signIn } from "./support";

// Sign in once per account and reuse the session, so the tests stay under
// the sign-in rate limits.
setup("sign in as the manager", async ({ page }) => {
  await signIn(page, MANAGER);
  await page.context().storageState({ path: MANAGER_STATE });
});

setup("sign in as the admin", async ({ page }) => {
  await signIn(page, ADMIN);
  await page.context().storageState({ path: ADMIN_STATE });
});
