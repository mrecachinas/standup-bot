import { Link as RouterLink, useSearchParams } from "react-router";
import { Button, UnderlineNav } from "@primer/react";
import { HashIcon, PeopleIcon, SearchIcon } from "@primer/octicons-react";
import type { IntegrationsPayload } from "../../api/types/chat";
import { ErrorBanner, LoadingState, PageHeader, StatusLabel } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { ChatStatusPanel } from "./chat/ChatStatusPanel";
import { DiscoveryResults } from "./chat/DiscoveryResults";
import { InlineInputForm } from "./chat/InlineInputForm";
import { Panel, PanelEmptyText, PanelList, PanelListItem } from "./insights/Panel";
import chatStyles from "./chat/chat.module.css";
import styles from "./insights/insights.module.css";

const QUERY_PARAMS = ["platform", "channel_query", "user_query", "discover"] as const;
const DESCRIPTION = "Connection health and workspace lookup for each chat platform. Secrets are never shown.";

export function IntegrationsPage() {
  useDocumentTitle("Integrations");
  const [searchParams, setSearchParams] = useSearchParams();
  const query = new URLSearchParams();
  for (const key of QUERY_PARAMS) {
    const value = searchParams.get(key);
    if (value) query.set(key, value);
  }
  const queryString = query.toString();
  const { data, error, loading, reload } = useApi<IntegrationsPayload>(queryString ? `/api/integrations?${queryString}` : "/api/integrations");

  const header = <PageHeader title="Integrations" description={DESCRIPTION} />;

  if (!data) {
    return (
      <div className={styles.page}>
        {header}
        {error ? (
          <ErrorBanner
            error={error}
            title="Couldn't load integrations"
            action={<Button onClick={reload}>Try again</Button>}
          />
        ) : (
          <LoadingState label="Checking integrations…" />
        )}
      </div>
    );
  }

  const platform = data.platform;
  const label = data.integration_status.label;
  const discover = searchParams.get("discover");

  const search = (kind: "channels" | "users", value: string) => {
    const next = new URLSearchParams({ platform, discover: kind });
    if (value) next.set(kind === "channels" ? "channel_query" : "user_query", value);
    setSearchParams(next);
  };

  return (
    <div className={styles.page}>
      <div>
        {header}
        <UnderlineNav aria-label="Chat platforms">
          {data.platforms.map((tab) => (
            <UnderlineNav.Item
              key={tab.key}
              as={RouterLink}
              to={`${paths.integrations}?platform=${tab.key}`}
              aria-current={tab.key === platform ? "page" : undefined}
              leadingVisual={tab.icon === "people" ? <PeopleIcon /> : <HashIcon />}
            >
              {tab.label}
              <StatusLabel tone={tab.status_tone} className={chatStyles.tabCount}>
                {tab.status_label}
              </StatusLabel>
            </UnderlineNav.Item>
          ))}
        </UnderlineNav>
      </div>

      <ErrorBanner error={error} title="Couldn't refresh integrations" />

      <div className={styles.mainAside}>
        <div className={styles.page}>
          <ChatStatusPanel status={data.integration_status} />

          <Panel title={`Look up ${label} channels and people`} description="Find the IDs to use in standups and reports." flush>
            <div className={chatStyles.discoveryGrid}>
              <div id={`${platform}-channel-discovery`} className={chatStyles.discoveryColumn}>
                <div className={chatStyles.bodyStack}>
                  <InlineInputForm
                    key={`${platform}:channels:${data.channel_query ?? ""}`}
                    type="search"
                    label="Search channels"
                    name="channel_query"
                    submitLabel="Find channels"
                    leadingVisual={SearchIcon}
                    initialValue={data.channel_query ?? ""}
                    placeholder={data.copy.channel_search_placeholder}
                    loading={loading && discover === "channels"}
                    onSubmit={(value) => search("channels", value)}
                  />
                </div>
                {data.channel_result && (
                  <div className={chatStyles.section}>
                    <DiscoveryResults result={data.channel_result} label="Channel results" emptyMessage="No channels matched." />
                  </div>
                )}
              </div>
              <div id={`${platform}-user-discovery`} className={chatStyles.discoveryColumn}>
                <div className={chatStyles.bodyStack}>
                  <InlineInputForm
                    key={`${platform}:users:${data.user_query ?? ""}`}
                    type="search"
                    label="Search people"
                    name="user_query"
                    submitLabel="Find users"
                    leadingVisual={SearchIcon}
                    initialValue={data.user_query ?? ""}
                    placeholder={data.copy.user_search_placeholder}
                    loading={loading && discover === "users"}
                    onSubmit={(value) => search("users", value)}
                  />
                </div>
                {data.user_result && (
                  <div className={chatStyles.section}>
                    <DiscoveryResults result={data.user_result} label="People results" emptyMessage="No users matched." />
                  </div>
                )}
              </div>
            </div>
          </Panel>
        </div>

        <aside aria-label="Your standups">
          <Panel title="Standups" flush>
            {data.standups.length > 0 ? (
              <PanelList label="Standups">
                {data.standups.map((standup) => (
                  <PanelListItem
                    key={standup.id}
                    leadingVisual={
                      <span
                        className={`${chatStyles.dot} ${standup.active ? chatStyles.dotSuccess : chatStyles.dotWarning}`}
                        role="img"
                        aria-label={standup.active ? "Active" : "Paused"}
                      />
                    }
                    title={standup.name}
                    description={
                      <>
                        {standup.platform_label} · <span className={chatStyles.mono}>{standup.channel_reference}</span>
                      </>
                    }
                    trailing={
                      <Button as={RouterLink} to={paths.editStandup(standup.id)} size="small" aria-label={`Configure ${standup.name}`}>
                        Configure
                      </Button>
                    }
                  />
                ))}
              </PanelList>
            ) : (
              <PanelEmptyText>No standups are assigned to you yet.</PanelEmptyText>
            )}
          </Panel>
        </aside>
      </div>
    </div>
  );
}
