import { post } from "../../../api/client";
import type { ScheduleExceptionParams, ScheduleExceptionResult } from "../../../api/types/roster";

/** POST /api/standups/:id/schedule_exceptions. */
export function createScheduleException(standupId: number | string, params: ScheduleExceptionParams) {
  return post<ScheduleExceptionResult>(`/api/standups/${standupId}/schedule_exceptions`, { schedule_exception: params });
}

/** The zone list with `current` first if the list doesn't have it. */
export function zoneOptions(options: string[], current: string): string[] {
  return options.includes(current) ? options : [current, ...options];
}
