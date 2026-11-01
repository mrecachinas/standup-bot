import type { ApiError } from "../../../api/client";

/**
 * A field's 422 message for FormControl.Validation. Rails sends attribute
 * messages without the attribute ("can't be blank"), so prefix the label.
 */
export function fieldMessage(error: ApiError | null | undefined, field: string, label: string): string | undefined {
  const message = error?.fieldError(field);
  if (!message) return undefined;
  return /^[a-z]/.test(message) ? `${label} ${message}` : message;
}

/**
 * Messages for the form's Banner: the `base` errors when the server sent
 * field errors (the rest show on their fields), otherwise every message.
 */
export function baseMessages(error: ApiError | null | undefined, fields: string[]): string[] {
  if (!error) return [];
  const fieldErrors = error.fieldErrors;
  const shownOnFields = fields.some((field) => (fieldErrors[field]?.length ?? 0) > 0);
  if (!shownOnFields) return error.errors;

  const base = fieldErrors.base ?? [];
  const unshown = Object.entries(fieldErrors)
    .filter(([field]) => field !== "base" && !fields.includes(field))
    .flatMap(([, messages]) => messages);
  return [...base, ...unshown];
}
