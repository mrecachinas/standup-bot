import { useParams } from "react-router";
import type { StandupFormPayload } from "../../api/types/standups";
import { LoadingState, StandupHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { StandupForm } from "./standupForm/StandupForm";
import { StandupLoadError } from "./standups/StandupLoadError";
import { usePauseResume } from "./standups/usePauseResume";
import styles from "./standups/standups.module.css";

/** /manager/standups/:id/edit: the standup's Settings tab. */
export function EditStandupPage() {
  const { id = "" } = useParams();
  const { data, error, loading, reload, setData } = useApi<StandupFormPayload>(`/api/standups/${id}/edit`);
  useDocumentTitle(data ? `Settings · ${data.standup.name}` : "Settings");
  const pauseResume = usePauseResume((result) => {
    setData((current) => ({ ...current!, standup: { ...current!.standup, active: result.standup.active } }));
  });

  if (!data) {
    if (error) return <StandupLoadError error={error} onRetry={reload} title="Settings" />;
    return loading ? <LoadingState label="Loading settings…" /> : null;
  }

  const standup = { ...data.standup, id: data.standup.id ?? Number(id) };
  const activeParticipants = data.participant_rows.filter((row) => row.id !== null && row.active).length;

  return (
    <div className={styles.page}>
      <StandupHeader
        standup={standup}
        active="settings"
        participantCount={activeParticipants}
        onPauseResume={() => void pauseResume.run(standup.id, standup.active)}
        pauseResumeBusy={pauseResume.loading}
      />
      <StandupForm key={standup.id} payload={data} />
    </div>
  );
}
