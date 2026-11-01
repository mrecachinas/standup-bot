import { patch } from "../../../api/client";
import type { Standup } from "../../../api/types";
import { useMutation } from "../../../hooks/useMutation";

interface PauseResumeResponse {
  standup: Standup;
  notice?: string;
}

/**
 * Pause/Resume for StandupHeader: PATCH /api/standups/:id/pause|resume, flash
 * the notice, refresh the sidebar and hand the updated standup back.
 */
export function useStandupPauseResume(standup: Pick<Standup, "id" | "active"> | undefined, onUpdated: (standup: Standup) => void) {
  const mutation = useMutation(
    (target: Pick<Standup, "id" | "active">) => patch<PauseResumeResponse>(`/api/standups/${target.id}/${target.active ? "pause" : "resume"}`),
    { refreshSidebar: true, flashError: true, onSuccess: (result) => onUpdated(result.standup) },
  );

  return {
    onPauseResume: standup ? () => mutation.run(standup).then(() => undefined) : undefined,
    busy: mutation.loading,
  };
}
