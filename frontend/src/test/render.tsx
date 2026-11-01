import { render } from "@testing-library/react";
import { createMemoryRouter } from "react-router";
import { vi } from "vitest";
import { App } from "../App";
import { routes } from "../router";
import type { Bootstrap } from "../api/types";
import { jsonResponse } from "./fixtures";

type Handler = (url: string, init: RequestInit) => Response | undefined | Promise<Response | undefined>;

/** Stubs fetch: GET /api/session returns `bootstrap`; other calls go to `handler`. */
export function mockFetch(bootstrap: Bootstrap, handler?: Handler) {
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = String(input);
    const method = init.method ?? "GET";
    if (handler) {
      const response = await handler(url, { ...init, method });
      if (response) return response;
    }
    if (url === "/api/session" && method === "GET") return jsonResponse(bootstrap);
    return jsonResponse({ error: "Not found" }, 404);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

/** Renders the whole app at `path` with a memory router. */
export function renderApp(path: string) {
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const utils = render(<App router={router} />);
  return { ...utils, router };
}
