import type { StandupManager } from "../../../api/types/roster";
import { Avatar, ConfirmButton, Panel } from "../../../components";
import layout from "../../../styles/layout.module.css";
import { removeManagerCopy } from "./managerCopy";

export interface ManagersSectionProps {
  standupName: string;
  managers: StandupManager[];
  onRemove: (manager: StandupManager) => Promise<unknown>;
}

export function ManagersSection({ standupName, managers, onRemove }: ManagersSectionProps) {
  return (
    <Panel
      title="Managers"
      headingId="standup-managers-heading"
      id="standup-managers"
      flush
      description="Managers can change this standup's settings, people, and schedule. It doesn't give them access to any other standup."
    >
      {managers.length > 0 ? (
        <>
          <ul className={layout.list} aria-labelledby="standup-managers-heading">
            {managers.map((manager) => {
              const copy = removeManagerCopy(manager.name, standupName, manager.current_user);
              return (
                <li key={manager.id}>
                  <Avatar name={manager.name} src={manager.avatar_url} />
                  <div className={layout.grow}>
                    <div className={layout.title}>
                      {manager.name}
                      {manager.current_user && <span className={layout.hint}> (you)</span>}
                    </div>
                    <div className={layout.hint}>{manager.role_label}</div>
                  </div>
                  {manager.can_remove && (
                    <ConfirmButton
                      size="small"
                      variant="invisible"
                      aria-label={copy.title.replace(/\?$/, "")}
                      title={copy.title}
                      message={copy.message}
                      confirmLabel={copy.confirm}
                      danger
                      onConfirm={() => onRemove(manager)}
                    >
                      Remove
                    </ConfirmButton>
                  )}
                </li>
              );
            })}
          </ul>
          {managers.length === 1 && <p className={layout.empty}>Make someone else a manager from the list below before you can step down.</p>}
        </>
      ) : (
        <p className={layout.empty}>Only admins manage this standup right now. Make someone a manager from the list below.</p>
      )}
    </Panel>
  );
}
