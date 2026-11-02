import { Banner, Label } from "@primer/react";
import { CheckCircleIcon, InfoIcon, XCircleIcon } from "@primer/octicons-react";
import type { ChatStatus } from "../../../api/types/chat";
import { KeyValueList, Panel, PanelList, PanelListItem, StatusLabel } from "../../../components";
import styles from "./chat.module.css";

/** "<Platform> app status": credentials checklist plus the live API check. */
export function ChatStatusPanel({ status }: { status: ChatStatus }) {
  const label = status.label;
  const connection = status.connection;

  return (
    <Panel
      id={`${status.platform}-status`}
      title={status.title || `${label} app status`}
      description={status.installation?.message}
      actions={<StatusLabel tone={status.status_tone}>{status.status_label}</StatusLabel>}
      flush
    >
      <PanelList label={`${label} credentials`}>
        {status.credentials.map((credential) => {
          const Icon = credential.configured ? CheckCircleIcon : credential.required ? XCircleIcon : InfoIcon;
          const toneClass = credential.configured ? styles.success : credential.required ? styles.warning : styles.subtle;
          return (
            <PanelListItem
              key={credential.key}
              id={`${status.platform}-credential-${credential.key}`}
              leadingVisual={<Icon className={toneClass} size={16} />}
              title={
                <>
                  {credential.label}
                  {!credential.required && <span className={styles.optional}> (optional)</span>}
                </>
              }
              description={credential.message}
              trailing={
                credential.configured ? (
                  <span className={styles.subtle}>{credential.state_label}</span>
                ) : (
                  <Label variant={credential.required ? "attention" : "secondary"}>{credential.state_label}</Label>
                )
              }
            />
          );
        })}
      </PanelList>

      {connection && (
        <div id={`${status.platform}-connection-health`} className={styles.connection}>
          <Banner
            variant={connection.success ? "success" : "warning"}
            title={`${label} API connection.`}
            description={
              <div className={styles.connectionBody}>
                <p>{connection.message}</p>
                {connection.success && connection.metadata && connection.metadata.length > 0 ? (
                  <KeyValueList items={connection.metadata.map((item) => ({ label: item.label, value: String(item.value ?? "—") }))} />
                ) : (
                  connection.action && <p>Next step: {connection.action}</p>
                )}
              </div>
            }
          />
        </div>
      )}
    </Panel>
  );
}
