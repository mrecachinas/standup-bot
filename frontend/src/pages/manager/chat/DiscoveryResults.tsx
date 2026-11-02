import type { ReactNode } from "react";
import { Banner } from "@primer/react";
import { HashIcon } from "@primer/octicons-react";
import type { ChatRecord, ChatResult } from "../../../api/types/chat";
import { Avatar } from "../../../components";
import { PanelEmptyText, PanelList, PanelListItem } from "../insights/Panel";
import styles from "./chat.module.css";

export interface DiscoveryResultsProps {
  result: ChatResult;
  /** "No channels matched." */
  emptyMessage: string;
  /** Accessible name for the result list. */
  label: string;
  /** e.g. a "Use channel" or "Add user" button. */
  renderAction?: (record: ChatRecord) => ReactNode;
}

/** Channels or people found by a discovery search, or why the search failed. */
export function DiscoveryResults({ result, emptyMessage, label, renderAction }: DiscoveryResultsProps) {
  if (!result.success) {
    return (
      <div className={styles.resultBanner}>
        <Banner
          variant="warning"
          title="Search failed"
          hideTitle
          description={
            <div className={styles.connectionBody}>
              <p>{result.message}</p>
              {result.action && <p>Next step: {result.action}</p>}
            </div>
          }
        />
      </div>
    );
  }

  const records = result.records ?? [];
  if (records.length === 0) return <PanelEmptyText>{emptyMessage}</PanelEmptyText>;

  return (
    <PanelList label={label}>
      {records.map((record) => (
        <PanelListItem
          key={record.id}
          leadingVisual={record.kind === "user" ? <Avatar name={record.label} src={record.avatar_url} size={24} /> : <HashIcon size={16} />}
          title={record.label}
          description={<span className={styles.mono}>{record.detail}</span>}
          trailing={renderAction?.(record)}
        />
      ))}
    </PanelList>
  );
}
