import type { ApiErrorBody, Bootstrap } from "./types";

export const SESSION_PATH = "/api/session";

/** A failed API request, parsed from `{ error }` or `{ errors, field_errors }`. */
export class ApiError extends Error {
  readonly status: number;
  readonly errors: string[];
  readonly fieldErrors: Record<string, string[]>;
  readonly body: unknown;

  constructor(status: number, body: unknown, fallback?: string) {
    const parsed = parseErrorBody(body);
    const message = parsed.message ?? fallback ?? defaultMessage(status);
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.errors = parsed.errors.length > 0 ? parsed.errors : [message];
    this.fieldErrors = parsed.fieldErrors;
    this.body = body;
  }

  /** First error for a form field (e.g. `"name"`), for `FormControl.Validation`. */
  fieldError(field: string): string | undefined {
    return this.fieldErrors[field]?.[0];
  }
}

export interface RequestOptions {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  /** Plain objects are sent as JSON; FormData is sent as-is. */
  body?: unknown;
  headers?: Record<string, string>;
  signal?: AbortSignal;
  /** Don't tell the session layer about a 401 (used by sign-in). */
  skipUnauthorizedHandler?: boolean;
}

interface SessionHooks {
  /** Called with a fresh bootstrap after the client re-fetched GET /api/session. */
  onBootstrap?: (bootstrap: Bootstrap) => void;
  /** Called when a request comes back 401 (the session expired or was revoked). */
  onUnauthorized?: () => void;
}

let csrfToken: string | null = null;
let hooks: SessionHooks = {};

/** The session layer keeps the client's CSRF token in sync with the bootstrap. */
export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

export function getCsrfToken(): string | null {
  return csrfToken;
}

export function configureSessionHooks(next: SessionHooks): void {
  hooks = next;
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const response = await send(path, options);

  if (response.status === 422 && options.method && options.method !== "GET") {
    const body = await readBody(response);
    if (isInvalidAuthenticityToken(body)) {
      await refreshSession();
      return finish<T>(await send(path, options), options);
    }
    throw new ApiError(response.status, body);
  }

  return finish<T>(response, options);
}

export function get<T>(path: string, options: Omit<RequestOptions, "method" | "body"> = {}): Promise<T> {
  return request<T>(path, { ...options, method: "GET" });
}

export function post<T>(path: string, body?: unknown, options: Omit<RequestOptions, "method" | "body"> = {}): Promise<T> {
  return request<T>(path, { ...options, method: "POST", body });
}

export function patch<T>(path: string, body?: unknown, options: Omit<RequestOptions, "method" | "body"> = {}): Promise<T> {
  return request<T>(path, { ...options, method: "PATCH", body });
}

export function put<T>(path: string, body?: unknown, options: Omit<RequestOptions, "method" | "body"> = {}): Promise<T> {
  return request<T>(path, { ...options, method: "PUT", body });
}

export function del<T = void>(path: string, body?: unknown, options: Omit<RequestOptions, "method" | "body"> = {}): Promise<T> {
  return request<T>(path, { ...options, method: "DELETE", body });
}

export const api = { request, get, post, patch, put, del };

/** Re-fetches the bootstrap, updating the CSRF token. */
export async function refreshSession(): Promise<Bootstrap> {
  const response = await send(SESSION_PATH, { method: "GET" });
  const body = await readBody(response);
  if (!response.ok) throw new ApiError(response.status, body);

  const bootstrap = body as Bootstrap;
  setCsrfToken(bootstrap.csrf_token);
  hooks.onBootstrap?.(bootstrap);
  return bootstrap;
}

function send(path: string, options: RequestOptions): Promise<Response> {
  const method = options.method ?? "GET";
  const headers: Record<string, string> = { Accept: "application/json", ...options.headers };
  let body: BodyInit | undefined;

  if (options.body instanceof FormData) {
    body = options.body;
  } else if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(options.body);
  }

  if (method !== "GET" && csrfToken) headers["X-CSRF-Token"] = csrfToken;

  return fetch(path, { method, headers, body, credentials: "same-origin", signal: options.signal });
}

async function finish<T>(response: Response, options: RequestOptions): Promise<T> {
  const body = await readBody(response);

  if (response.ok) return body as T;

  if (response.status === 401 && !options.skipUnauthorizedHandler) hooks.onUnauthorized?.();
  throw new ApiError(response.status, body);
}

async function readBody(response: Response): Promise<unknown> {
  if (response.status === 204) return undefined;

  const text = await response.text();
  if (!text) return undefined;

  const type = response.headers.get("Content-Type") ?? "";
  if (type.includes("json")) {
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }
  return text;
}

function isInvalidAuthenticityToken(body: unknown): boolean {
  return isRecord(body) && typeof body.error === "string" && /invalid authenticity token/i.test(body.error);
}

function parseErrorBody(body: unknown): { message?: string; errors: string[]; fieldErrors: Record<string, string[]> } {
  if (!isRecord(body)) {
    return { message: typeof body === "string" && body.trim() && body.length < 300 ? body.trim() : undefined, errors: [], fieldErrors: {} };
  }

  const { error, errors, field_errors: fieldErrors } = body as ApiErrorBody;
  const list = Array.isArray(errors) ? errors.filter((item): item is string => typeof item === "string") : [];
  if (typeof error === "string" && error) list.unshift(error);
  const unique = [...new Set(list)];

  return {
    message: unique.length > 0 ? unique.join(" ") : undefined,
    errors: unique,
    fieldErrors: isRecord(fieldErrors) ? (fieldErrors as Record<string, string[]>) : {},
  };
}

function defaultMessage(status: number): string {
  switch (status) {
    case 401:
      return "Your session has ended. Sign in again.";
    case 403:
      return "You don't have access to that.";
    case 404:
      return "That page or record doesn't exist.";
    case 0:
      return "Couldn't reach the server.";
    default:
      return status >= 500 ? "Something went wrong on the server. Try again." : `Request failed (${status}).`;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
