import type { ReactNode } from "react";
import { Banner } from "@primer/react";
import { HashIcon } from "@primer/octicons-react";
import type { ChatRecord, ChatResult } from "../../../api/types/chat";
import { Avatar, PanelEmptyText, PanelList, PanelListItem } from "../../../components";
import layout from "../../../styles/layout.module.css";
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
  // e.g. private Slack channels left out because the app lacks a scope.
  const note = result.action && (
    <div className={styles.resultBanner}>
      <Banner variant="info" title="Some results are hidden" hideTitle description={result.action} />
    </div>
  );
  if (records.length === 0)
    return (
      <>
        {note}
        <PanelEmptyText>{emptyMessage}</PanelEmptyText>
      </>
    );

  return (
    <>
      {note}
      <PanelList label={label}>
      {records.map((record) => (
        <PanelListItem
          key={record.id}
          leadingVisual={record.kind === "user" ? <Avatar name={record.label} src={record.avatar_url} size={24} /> : <HashIcon size={16} />}
          title={record.label}
          description={<span className={layout.mono}>{record.detail}</span>}
          trailing={renderAction?.(record)}
        />
      ))}
      </PanelList>
    </>
  );
}
