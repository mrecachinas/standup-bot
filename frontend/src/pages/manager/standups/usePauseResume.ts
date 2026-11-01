import { patch } from "../../../api/client";
import type { StandupMutationResult } from "../../../api/types/standups";
import { useMutation } from "../../../hooks/useMutation";

/**
 * PATCH /api/standups/:id/pause or /resume, then refresh the sidebar.
 * `run(id, active)` pauses an active standup and resumes a paused one.
 */
export function usePauseResume(onSuccess?: (result: StandupMutationResult) => void | Promise<void>) {
  return useMutation(
    (id: number | string, active: boolean) => patch<StandupMutationResult>(`/api/standups/${id}/${active ? "pause" : "resume"}`),
    { onSuccess, refreshSidebar: true, flashError: true },
  );
}
