import { ApiError } from "../api/client";

/** Human-readable messages for an ApiError, Error or string. */
export function errorMessages(error: unknown): string[] {
  if (!error) return [];
  if (error instanceof ApiError) return error.errors;
  if (error instanceof Error) return [error.message];
  if (typeof error === "string") return [error];
  return ["Something went wrong."];
}
