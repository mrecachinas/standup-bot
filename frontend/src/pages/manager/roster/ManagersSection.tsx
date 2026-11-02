import type { StandupManager } from "../../../api/types/roster";
import { Avatar, ConfirmButton } from "../../../components";
import { Section } from "./Section";
import styles from "./roster.module.css";

export interface ManagersSectionProps {
  standupName: string;
  managers: StandupManager[];
  onRemove: (manager: StandupManager) => Promise<unknown>;
}

export function ManagersSection({ standupName, managers, onRemove }: ManagersSectionProps) {
  return (
    <Section
      title="Managers"
      titleId="standup-managers-heading"
      id="standup-managers"
      hint="Managers can change this standup's settings, people, and schedule. It doesn't give them access to any other standup."
    >
      {managers.length > 0 ? (
        <>
          <ul className={styles.list} aria-labelledby="standup-managers-heading">
            {managers.map((manager) => (
              <li key={manager.id} className={styles.listItem}>
                <Avatar name={manager.name} src={manager.avatar_url} />
                <div className={styles.grow}>
                  <div className={styles.cellTitle}>
                    {manager.name}
                    {manager.current_user && <span className={styles.subtle}> (you)</span>}
                  </div>
                  <div className={styles.cellSub}>{manager.role_label}</div>
                </div>
                {manager.can_remove && (
                  <ConfirmButton
                    size="small"
                    variant="invisible"
                    aria-label={manager.current_user ? `Stop managing ${standupName}` : `Remove ${manager.name} as a manager`}
                    title={manager.current_user ? `Stop managing ${standupName}?` : `Remove ${manager.name}?`}
                    message={
                      manager.current_user
                        ? `Stop managing ${standupName}? You'll lose access to it.`
                        : `Remove ${manager.name} as a manager of ${standupName}?`
                    }
                    confirmLabel="Remove"
                    danger
                    onConfirm={() => onRemove(manager)}
                  >
                    Remove
                  </ConfirmButton>
                )}
              </li>
            ))}
          </ul>
          {managers.length === 1 && managers[0].current_user && <p className={styles.emptyInline}>Make someone else a manager from the list below before you can step down.</p>}
        </>
      ) : (
        <p className={styles.emptyInline}>Only admins manage this standup right now. Make someone a manager from the list below.</p>
      )}
    </Section>
  );
}
