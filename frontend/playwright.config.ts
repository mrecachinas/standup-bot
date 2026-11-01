import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.E2E_PORT ?? 3100);

/**
 * End-to-end smoke tests against a real Rails server serving the built
 * console (script/e2e-server). Run `npm run build` first.
 */
export default defineConfig({
  testDir: "./e2e",
  // The tests share one database, so run them one at a time.
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    { name: "light", use: { ...devices["Desktop Chrome"], colorScheme: "light" }, dependencies: ["setup"] },
    { name: "dark", use: { ...devices["Desktop Chrome"], colorScheme: "dark" }, dependencies: ["setup"] },
  ],
  webServer: {
    command: "../script/e2e-server",
    url: `http://127.0.0.1:${port}/up`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    env: { E2E_PORT: String(port) },
    stdout: "ignore",
    stderr: "pipe",
  },
});
