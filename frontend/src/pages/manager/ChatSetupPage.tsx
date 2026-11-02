import { Link as RouterLink, useParams, useSearchParams } from "react-router";
import { Banner, Button } from "@primer/react";
import { PaperAirplaneIcon, PeopleIcon, SearchIcon } from "@primer/octicons-react";
import { ApiError, patch, post } from "../../api/client";
import type { ChatResult, ChatSetupPayload } from "../../api/types/chat";
import { ErrorBanner, Panel, PanelBody, StandupHeader } from "../../components";
import { useForwardedQuery } from "../../hooks/useForwardedQuery";
import { useMutation } from "../../hooks/useMutation";
import { paths } from "../../paths";
import { ChatStatusPanel } from "./chat/ChatStatusPanel";
import { DiscoveryResults } from "./chat/DiscoveryResults";
import { InlineInputForm } from "./chat/InlineInputForm";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";
import chatStyles from "./chat/chat.module.css";

export function ChatSetupPage() {
  const { id = "" } = useParams();
  const base = `/api/standups/${id}/chat_setup`;
  const [searchParams, setSearchParams] = useSearchParams();
  const path = useForwardedQuery(base, ["channel_query", "discover"]);
  const { data, error, loading, reload, setData, setStandup } = useStandupPage<ChatSetupPayload>(path, (payload) => payload.platform.label);

  const updateChannel = useMutation((body: { channel_id: string; channel_name?: string | null }) => patch<ChatSetupPayload>(`${base}/channel`, body), {
    onSuccess: (result) => setData(result),
  });
  // The test message doesn't change the channel, so keep any search results on screen.
  const testMessage = useMutation(() => post<ChatSetupPayload>(`${base}/test_message`), {
    onSuccess: (result) => setData((current) => ({ ...result, channel_query: current?.channel_query ?? null, channel_result: current?.channel_result ?? null })),
  });

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Chat setup" />;

  const { standup, platform, channel, copy } = data;
  const failedTest = testMessageFailure(testMessage.error);
  const channelFieldError = updateChannel.error?.fieldError("channel_id");

  const searchChannels = (value: string) => {
    const next = new URLSearchParams({ discover: "channels" });
    if (value) next.set("channel_query", value);
    setSearchParams(next);
  };

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="chat" onStandupChange={setStandup} />

      <ErrorBanner error={error} title="Couldn't search" />

      <div className={layout.mainAside}>
        <Panel
          id={`${platform.key}-channel-setup`}
          title="Summary channel"
          description={
            <>
              Currently posting to <span className={layout.mono}>{channel.channel_reference}</span>
            </>
          }
          flush
        >
          <PanelBody>
            {updateChannel.error && !channelFieldError && <ErrorBanner error={updateChannel.error} title="Couldn't update the channel" />}
            <InlineInputForm
              key={channel.platform_channel ?? ""}
              label="Channel ID"
              name="channel_id"
              submitLabel="Save channel"
              initialValue={channel.platform_channel ?? ""}
              placeholder={copy.channel_id_placeholder}
              loading={updateChannel.loading}
              validation={channelFieldError}
              onSubmit={(value) => void updateChannel.run({ channel_id: value })}
            />
            <InlineInputForm
              key={`channels:${data.channel_query ?? ""}`}
              type="search"
              label="Search channels"
              name="channel_query"
              submitLabel="Find channels"
              leadingVisual={SearchIcon}
              initialValue={data.channel_query ?? ""}
              placeholder={copy.channel_search_placeholder}
              loading={loading && searchParams.get("discover") === "channels"}
              onSubmit={searchChannels}
            />
          </PanelBody>
          {data.channel_result && (
            <div id={`${platform.key}-channel-results`} className={chatStyles.section}>
              <DiscoveryResults
                result={data.channel_result}
                label="Channel results"
                emptyMessage="No channels matched."
                renderAction={(record) => (
                  <Button size="small" onClick={() => void updateChannel.run({ channel_id: record.id, channel_name: record.name })} aria-label={`Use channel ${record.label}`}>
                    Use channel
                  </Button>
                )}
              />
            </div>
          )}
        </Panel>

        <aside className={layout.stack} aria-label={`${platform.label} status`}>
          <Panel id={`${platform.key}-test-message`} title="Test message">
            <p className={layout.hint}>
              Posts a short message to <span className={layout.mono}>{channel.channel_reference}</span> so you can confirm the bot can reach it.
            </p>
            {testMessage.error && (
              <Banner
                variant="warning"
                title="Test message failed"
                hideTitle
                description={
                  <div className={chatStyles.connectionBody}>
                    <p>{failedTest?.message ?? testMessage.error.message}</p>
                    {failedTest?.action && <p>Next step: {failedTest.action}</p>}
                  </div>
                }
              />
            )}
            <Button leadingVisual={PaperAirplaneIcon} onClick={() => void testMessage.run()} loading={testMessage.loading} block>
              Send test message
            </Button>
          </Panel>

          <Panel
            title="People"
            actions={
              <Button as={RouterLink} to={paths.standupParticipants(standup.id)} size="small" leadingVisual={PeopleIcon}>
                Manage participants
              </Button>
            }
          >
            <p className={layout.hint}>Add, sync, and remove people on the Participants tab.</p>
          </Panel>

          <ChatStatusPanel status={data.integration_status} />
        </aside>
      </div>
    </div>
  );
}

function testMessageFailure(error: ApiError | null): ChatResult | null {
  if (!error || typeof error.body !== "object" || error.body === null) return null;
  return (error.body as { test_message?: ChatResult }).test_message ?? null;
}
