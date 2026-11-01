import type { Bootstrap } from "../api/types";

export const SIGN_IN_PATH = "/session/new";

/** /session/new?next=<path> for the page someone tried to open. */
export function signInPath(next?: string): string {
  if (!next || next === "/" || next.startsWith(SIGN_IN_PATH)) return SIGN_IN_PATH;
  return `${SIGN_IN_PATH}?next=${encodeURIComponent(next)}`;
}

/** Only same-origin, absolute paths are honoured as ?next= targets. */
export function safeNextPath(next: string | null | undefined): string | null {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return null;
  if (next.startsWith(SIGN_IN_PATH)) return null;
  return next;
}

/** Where "/" sends someone. */
export function homePath(bootstrap: Bootstrap): string {
  if (bootstrap.user) return "/manager/standups";
  if (bootstrap.member) return "/me";
  return SIGN_IN_PATH;
}

/** Whether this bootstrap can open `path` (used to decide if /session/new should redirect). */
export function canAccess(bootstrap: Bootstrap, path: string): boolean {
  if (/^\/(manager|admin)(\/|$|\?)/.test(path)) return Boolean(bootstrap.user);
  if (/^\/me(\/|$|\?)/.test(path)) return Boolean(bootstrap.member);
  return bootstrap.authenticated;
}
