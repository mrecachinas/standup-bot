import { useParams } from "react-router";
import type { StandupFormPayload } from "../../api/types/standups";
import { StandupHeader } from "../../components";
import { StandupForm } from "./standupForm/StandupForm";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";

/** /manager/standups/:id/edit: the standup's Settings tab. */
export function EditStandupPage() {
  const { id = "" } = useParams();
  const { data, error, reload, setStandup } = useStandupPage<StandupFormPayload>(`/api/standups/${id}/edit`, "Settings");

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Settings" />;

  const standup = { ...data.standup, id: data.standup.id ?? Number(id) };
  const activeParticipants = data.participant_rows.filter((row) => row.id !== null && row.active).length;

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="settings" participantCount={activeParticipants} onStandupChange={setStandup} />
      <StandupForm key={standup.id} payload={data} />
    </div>
  );
}
