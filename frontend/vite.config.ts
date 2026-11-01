/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rails = "http://localhost:3000";

// The built console is served by Rails at every console URL (SpaController),
// with its assets under /app/. The dev server uses "/" so its history fallback
// can serve index.html at any console path, and forwards API and sign-in
// requests to Rails.
export default defineConfig(({ command }) => ({
  base: command === "build" ? "/app/" : "/",
  plugins: [react()],
  build: {
    outDir: "../public/app",
    emptyOutDir: true,
    // Primer React is most of the bundle; an internal console can afford it.
    chunkSizeWarningLimit: 1000,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": { target: rails, changeOrigin: false },
      "/auth": { target: rails, changeOrigin: false },
    },
  },
  appType: "spa",
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.{ts,tsx}"],
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: false,
    restoreMocks: true,
    // Primer React imports its CSS Modules from JS; let Vite transform it.
    server: { deps: { inline: [/@primer\/react/] } },
  },
}));
