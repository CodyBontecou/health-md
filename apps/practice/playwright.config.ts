import { defineConfig, devices } from "@playwright/test";

const localPort = process.env.PRACTICE_E2E_PORT ?? String(20_000 + (process.pid % 20_000));
process.env.PRACTICE_E2E_PORT = localPort;
const baseURL = `https://127.0.0.1:${localPort}`;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 10_000 },
  reporter: [["line"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  outputDir: "test-results",
  use: {
    baseURL,
    serviceWorkers: "block",
    ignoreHTTPSErrors: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "off",
  },
  webServer: {
    command: "npm start",
    url: `${baseURL}/api/v1/meta`,
    timeout: 60_000,
    reuseExistingServer: false,
    ignoreHTTPSErrors: true,
    env: { WRANGLER_SEND_METRICS: "false", PRACTICE_LOCAL_PORT: localPort, PRACTICE_LOCAL_PROTOCOL: "https" },
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
});
