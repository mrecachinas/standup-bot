import { Link as RouterLink, useSearchParams } from "react-router";
import { Button, UnderlineNav } from "@primer/react";
import { HashIcon, PeopleIcon, SearchIcon } from "@primer/octicons-react";
import type { IntegrationsPayload } from "../../api/types/chat";
import { ErrorBanner, LoadingState, PageHeader, Panel, PanelBody, PanelEmptyText, PanelList, PanelListItem, StatusDot, StatusLabel } from "../../components";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useApi } from "../../hooks/useApi";
import { useForwardedQuery } from "../../hooks/useForwardedQuery";
import { paths } from "../../paths";
import { ChatStatusPanel } from "./chat/ChatStatusPanel";
import { DiscoveryResults } from "./chat/DiscoveryResults";
import { InlineInputForm } from "./chat/InlineInputForm";
import layout from "../../styles/layout.module.css";
import chatStyles from "./chat/chat.module.css";

const DESCRIPTION = "Connection health and workspace lookup for each chat platform. Secrets are never shown.";

export function IntegrationsPage() {
  useDocumentTitle("Integrations");
  const [searchParams, setSearchParams] = useSearchParams();
  const path = useForwardedQuery("/api/integrations", ["platform", "channel_query", "user_query", "discover"]);
  const { data, error, loading, reload } = useApi<IntegrationsPayload>(path);

  const header = <PageHeader title="Integrations" description={DESCRIPTION} />;

  if (!data) {
    return (
      <div className={layout.page}>
        {header}
        {error ? <ErrorBanner error={error} title="Couldn't load integrations" action={<Button onClick={reload}>Try again</Button>} /> : <LoadingState label="Checking integrations…" />}
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

  const columns = [
    { kind: "channels", id: `${platform}-channel-discovery`, label: "Search channels", name: "channel_query", submitLabel: "Find channels", query: data.channel_query, placeholder: data.copy.channel_search_placeholder, result: data.channel_result, resultLabel: "Channel results", emptyMessage: "No channels matched." },
    { kind: "users", id: `${platform}-user-discovery`, label: "Search people", name: "user_query", submitLabel: "Find users", query: data.user_query, placeholder: data.copy.user_search_placeholder, result: data.user_result, resultLabel: "People results", emptyMessage: "No users matched." },
  ] as const;

  return (
    <div className={layout.page}>
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

      <div className={layout.mainAside}>
        <div className={layout.stack}>
          <ChatStatusPanel status={data.integration_status} />

          <Panel title={`Look up ${label} channels and people`} description="Find the IDs to use in standups and reports." flush>
            <div className={chatStyles.discoveryGrid}>
              {columns.map((column) => (
                <div key={column.kind} id={column.id} className={chatStyles.discoveryColumn}>
                  <PanelBody>
                    <InlineInputForm
                      key={`${platform}:${column.kind}:${column.query ?? ""}`}
                      type="search"
                      label={column.label}
                      name={column.name}
                      submitLabel={column.submitLabel}
                      leadingVisual={SearchIcon}
                      initialValue={column.query ?? ""}
                      placeholder={column.placeholder}
                      loading={loading && discover === column.kind}
                      onSubmit={(value) => search(column.kind, value)}
                    />
                  </PanelBody>
                  {column.result && (
                    <div className={chatStyles.section}>
                      <DiscoveryResults result={column.result} label={column.resultLabel} emptyMessage={column.emptyMessage} />
                    </div>
                  )}
                </div>
              ))}
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
                    leadingVisual={<StatusDot tone={standup.active ? "success" : "warning"} label={standup.active ? "Active" : "Paused"} />}
                    title={standup.name}
                    description={
                      <>
                        {standup.platform_label} · <span className={layout.mono}>{standup.channel_reference}</span>
                      </>
                    }
                    trailing={
                      <Button as={RouterLink} to={paths.standupChatSetup(standup.id)} size="small" aria-label={`Configure ${standup.name}`}>
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
