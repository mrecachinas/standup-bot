import { describe, expect, it, vi } from "vitest";
import { ApiError, configureSessionHooks, del, get, patch, post, setCsrfToken } from "./client";
import { jsonResponse, signedOutBootstrap } from "../test/fixtures";

function stubFetch(...responses: Response[]) {
  const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
    const next = responses.shift();
    if (!next) throw new Error("unexpected fetch");
    return next;
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function headersOf(call: unknown[]): Record<string, string> {
  return ((call[1] as RequestInit).headers ?? {}) as Record<string, string>;
}

describe("api client", () => {
  it("sends JSON with the CSRF token and same-origin credentials on writes", async () => {
    setCsrfToken("token-1");
    const fetchMock = stubFetch(jsonResponse({ id: 1 }, 201));

    await expect(post("/api/standups", { standup: { name: "Daily" } })).resolves.toEqual({ id: 1 });

    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/standups");
    expect(init.method).toBe("POST");
    expect(init.credentials).toBe("same-origin");
    expect(init.body).toBe(JSON.stringify({ standup: { name: "Daily" } }));
    expect(headersOf(fetchMock.mock.calls[0])).toMatchObject({
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": "token-1",
    });
  });

  it("doesn't send the CSRF token on GET", async () => {
    setCsrfToken("token-1");
    const fetchMock = stubFetch(jsonResponse([]));

    await get("/api/standups");

    expect(headersOf(fetchMock.mock.calls[0])["X-CSRF-Token"]).toBeUndefined();
  });

  it("refreshes the session and retries once on an invalid authenticity token", async () => {
    setCsrfToken("stale");
    const onBootstrap = vi.fn();
    configureSessionHooks({ onBootstrap });
    const fetchMock = stubFetch(
      jsonResponse({ error: "Invalid authenticity token" }, 422),
      jsonResponse(signedOutBootstrap({ csrf_token: "fresh" })),
      jsonResponse({ ok: true }),
    );

    await expect(patch("/api/standups/1/pause")).resolves.toEqual({ ok: true });

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[1][0]).toBe("/api/session");
    expect(headersOf(fetchMock.mock.calls[0])["X-CSRF-Token"]).toBe("stale");
    expect(headersOf(fetchMock.mock.calls[2])["X-CSRF-Token"]).toBe("fresh");
    expect(onBootstrap).toHaveBeenCalledWith(expect.objectContaining({ csrf_token: "fresh" }));
  });

  it("only retries once", async () => {
    setCsrfToken("stale");
    const fetchMock = stubFetch(
      jsonResponse({ error: "Invalid authenticity token" }, 422),
      jsonResponse(signedOutBootstrap({ csrf_token: "fresh" })),
      jsonResponse({ error: "Invalid authenticity token" }, 422),
    );

    await expect(del("/api/standups/1")).rejects.toMatchObject({ status: 422, message: "Invalid authenticity token" });
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("parses validation errors and field errors", async () => {
    stubFetch(jsonResponse({ errors: ["Name can't be blank", "Channel is invalid"], field_errors: { name: ["can't be blank"] } }, 422));

    const error = await post("/api/standups", {}).catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(ApiError);
    const apiError = error as ApiError;
    expect(apiError.status).toBe(422);
    expect(apiError.errors).toEqual(["Name can't be blank", "Channel is invalid"]);
    expect(apiError.fieldErrors).toEqual({ name: ["can't be blank"] });
    expect(apiError.fieldError("name")).toBe("can't be blank");
    expect(apiError.message).toBe("Name can't be blank Channel is invalid");
  });

  it("parses { error } bodies", async () => {
    stubFetch(jsonResponse({ error: "Forbidden" }, 403));

    await expect(get("/api/admin/dashboard")).rejects.toMatchObject({ status: 403, message: "Forbidden", errors: ["Forbidden"], fieldErrors: {} });
  });

  it("doesn't repeat a message sent as both error and errors", async () => {
    stubFetch(jsonResponse({ error: "Pick a date.", errors: ["Pick a date."] }, 422));

    await expect(patch("/api/me/availability", {})).rejects.toMatchObject({ message: "Pick a date.", errors: ["Pick a date."] });
  });

  it("tells the session layer about a 401", async () => {
    const onUnauthorized = vi.fn();
    configureSessionHooks({ onUnauthorized });
    stubFetch(jsonResponse({ error: "Unauthorized" }, 401));

    await expect(get("/api/standups")).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
  });

  it("skips the 401 handler when asked (sign-in)", async () => {
    const onUnauthorized = vi.fn();
    configureSessionHooks({ onUnauthorized });
    stubFetch(jsonResponse({ error: "That email and access token don't match an active account." }, 401));

    await expect(post("/api/session", {}, { skipUnauthorizedHandler: true })).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  it("returns undefined for 204 responses", async () => {
    stubFetch(new Response(null, { status: 204 }));
    await expect(del("/api/standups/1")).resolves.toBeUndefined();
  });
});
