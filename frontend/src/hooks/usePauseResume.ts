import { patch } from "../api/client";
import type { Standup } from "../api/types";
import { useMutation } from "./useMutation";

interface PauseResumeResult {
  standup: Standup;
  notice: string | null;
}

/**
 * PATCH /api/standups/:id/pause (or /resume for a paused standup), flash the
 * notice and refresh the sidebar. `run(standup)` toggles it.
 */
export function usePauseResume(onUpdated?: (standup: Standup) => void | Promise<void>) {
  return useMutation(
    (standup: Pick<Standup, "id" | "active">) => patch<PauseResumeResult>(`/api/standups/${standup.id}/${standup.active ? "pause" : "resume"}`),
    { refreshSidebar: true, flashError: true, onSuccess: (result) => onUpdated?.(result.standup) },
  );
}
