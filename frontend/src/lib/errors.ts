import { ApiError } from "../api/client";

/** Human-readable messages for an ApiError, Error, string or list of messages. */
export function errorMessages(error: unknown): string[] {
  if (!error) return [];
  if (Array.isArray(error)) return error.filter((item): item is string => typeof item === "string" && item !== "");
  if (error instanceof ApiError) return error.errors;
  if (error instanceof Error) return [error.message];
  if (typeof error === "string") return [error];
  return ["Something went wrong."];
}
