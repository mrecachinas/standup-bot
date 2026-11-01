import { useState } from "react";
import { Link as RouterLink, useParams, useSearchParams } from "react-router";
import { Banner, Button } from "@primer/react";
import { PaperAirplaneIcon, PeopleIcon, SearchIcon } from "@primer/octicons-react";
import { ApiError, del, patch, post } from "../../api/client";
import type { ChatResult, ChatSetupParticipant, ChatSetupPayload } from "../../api/types/chat";
import { Avatar, ConfirmButton, ErrorBanner, LoadingState, StandupHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useMutation } from "../../hooks/useMutation";
import { paths } from "../../paths";
import { ChatStatusPanel } from "./chat/ChatStatusPanel";
import { DiscoveryResults } from "./chat/DiscoveryResults";
import { InlineInputForm } from "./chat/InlineInputForm";
import { PageLoadError } from "./insights/PageLoadError";
import { Panel, PanelList, PanelListItem } from "./insights/Panel";
import { useStandupPauseResume } from "./insights/useStandupPauseResume";
import chatStyles from "./chat/chat.module.css";
import styles from "./insights/insights.module.css";

const QUERY_PARAMS = ["channel_query", "user_query", "discover"] as const;

interface AddParticipantParams {
  user?: string;
  platform_user_id?: string;
  display_name?: string;
}

export function ChatSetupPage() {
  const { id = "" } = useParams();
  const base = `/api/standups/${id}/chat_setup`;
  const [searchParams, setSearchParams] = useSearchParams();
  const query = new URLSearchParams();
  for (const key of QUERY_PARAMS) {
    const value = searchParams.get(key);
    if (value) query.set(key, value);
  }
  const queryString = query.toString();

  const { data, error, loading, reload, setData } = useApi<ChatSetupPayload>(queryString ? `${base}?${queryString}` : base);
  const pauseResume = useStandupPauseResume(data?.standup, (standup) => setData((current) => ({ ...(current as ChatSetupPayload), standup })));
  const [addSource, setAddSource] = useState<"direct" | "result">("direct");
  useDocumentTitle(data ? `${data.platform.label} · ${data.standup.name}` : "Chat setup");

  // Writes return the payload without discovery results; keep the ones on screen.
  const apply = (result: ChatSetupPayload, keep: { channel?: boolean; user?: boolean } = { channel: true, user: true }) =>
    setData((current) => ({
      ...result,
      channel_query: result.channel_query ?? (keep.channel ? (current?.channel_query ?? null) : null),
      channel_result: result.channel_result ?? (keep.channel ? (current?.channel_result ?? null) : null),
      user_query: result.user_query ?? (keep.user ? (current?.user_query ?? null) : null),
      user_result: result.user_result ?? (keep.user ? (current?.user_result ?? null) : null),
    }));

  const search = (kind: "channels" | "users", value: string) => {
    const key = kind === "channels" ? "channel_query" : "user_query";
    const next = new URLSearchParams({ discover: kind });
    if (value) next.set(key, value);
    setSearchParams(next);
  };

  const updateChannel = useMutation((body: { channel_id: string; channel_name?: string | null }) => patch<ChatSetupPayload>(`${base}/channel`, body), {
    onSuccess: (result) => apply(result, { channel: false, user: true }),
  });
  const addParticipant = useMutation((body: AddParticipantParams) => post<ChatSetupPayload>(`${base}/participants`, body), { onSuccess: (result) => apply(result) });
  const removeParticipant = useMutation((participant: ChatSetupParticipant) => del<ChatSetupPayload>(`${base}/participants/${participant.id}`), {
    onSuccess: (result) => apply(result),
  });
  const testMessage = useMutation(() => post<ChatSetupPayload>(`${base}/test_message`), { onSuccess: (result) => apply(result) });

  if (!data) {
    if (error) return <PageLoadError error={error} onRetry={reload} />;
    return <LoadingState label="Loading chat setup…" />;
  }

  const { standup, platform, channel, copy } = data;
  const discover = searchParams.get("discover");
  const failedTest = testMessageFailure(testMessage.error);
  const channelFieldError = updateChannel.error?.fieldError("channel_id");
  const userFieldError = addSource === "direct" ? addParticipant.error?.fieldError("user") : undefined;
  const addError = addParticipant.error && !userFieldError ? addParticipant.error : null;

  return (
    <div className={styles.page}>
      <StandupHeader standup={standup} active="chat" onPauseResume={pauseResume.onPauseResume} pauseResumeBusy={pauseResume.busy} />

      <ErrorBanner error={error} title="Couldn't search" />

      <div className={styles.mainAside}>
        <div className={styles.page}>
          <Panel
            id={`${platform.key}-channel-setup`}
            title="Summary channel"
            description={
              <>
                Currently posting to <span className={chatStyles.mono}>{channel.channel_reference}</span>
              </>
            }
            flush
          >
            <div className={chatStyles.bodyStack}>
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
                loading={loading && discover === "channels"}
                onSubmit={(value) => search("channels", value)}
              />
            </div>
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

          <Panel
            id={`${platform.key}-participants-setup`}
            title={`Find people in ${platform.label}`}
            description="Search your workspace and add people to this standup."
            actions={
              <Button as={RouterLink} to={paths.standupParticipants(standup.id)} size="small" leadingVisual={PeopleIcon}>
                Manage participants
              </Button>
            }
            flush
          >
            <div className={chatStyles.bodyStack}>
              {addError && <ErrorBanner error={addError} title="Couldn't add the participant" />}
              {removeParticipant.error && <ErrorBanner error={removeParticipant.error} title="Couldn't remove the participant" />}
              <InlineInputForm
                key={`users:${data.user_query ?? ""}`}
                type="search"
                label="Search people"
                name="user_query"
                submitLabel="Find users"
                leadingVisual={SearchIcon}
                initialValue={data.user_query ?? ""}
                placeholder={copy.user_search_placeholder}
                loading={loading && discover === "users"}
                onSubmit={(value) => search("users", value)}
              />
              <InlineInputForm
                label="Add a person"
                name="user"
                submitLabel="Add user"
                placeholder={`Or add directly: ${copy.user_placeholder}`}
                loading={addParticipant.loading && addSource === "direct"}
                validation={userFieldError}
                onSubmit={async (value) => {
                  setAddSource("direct");
                  return (await addParticipant.run({ user: value })) !== undefined;
                }}
              />
            </div>
            {data.user_result && (
              <div className={chatStyles.section}>
                <DiscoveryResults
                  result={data.user_result}
                  label="People results"
                  emptyMessage="No users matched."
                  renderAction={(record) => (
                    <Button
                      size="small"
                      onClick={() => {
                        setAddSource("result");
                        void addParticipant.run({ platform_user_id: record.id, display_name: record.label });
                      }}
                      aria-label={`Add ${record.label}`}
                    >
                      Add user
                    </Button>
                  )}
                />
              </div>
            )}
            {data.participants.length > 0 && (
              <div className={chatStyles.section}>
                <PanelList label="Participants">
                  {data.participants.map((participant) => {
                    const name = participant.display_name || participant.platform_user_id;
                    return (
                      <PanelListItem
                        key={participant.id}
                        leadingVisual={<Avatar name={name} src={participant.avatar_url} size={24} />}
                        title={name}
                        description={
                          <>
                            <span className={chatStyles.mono}>{participant.platform_user_id}</span>
                            {!participant.active && " · inactive"}
                          </>
                        }
                        trailing={
                          <ConfirmButton
                            size="small"
                            variant="invisible"
                            title={`Remove ${name}?`}
                            message={`Remove ${name} from this standup?`}
                            confirmLabel="Remove"
                            danger
                            aria-label={`Remove ${name}`}
                            onConfirm={() => removeParticipant.run(participant)}
                          >
                            Remove
                          </ConfirmButton>
                        }
                      />
                    );
                  })}
                </PanelList>
              </div>
            )}
          </Panel>
        </div>

        <aside className={styles.page} aria-label={`${platform.label} status`}>
          <Panel id={`${platform.key}-test-message`} title="Test message">
            <p className={chatStyles.hint}>
              Posts a short message to <span className={chatStyles.mono}>{channel.channel_reference}</span> so you can confirm the bot can reach it.
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

          <ChatStatusPanel status={data.integration_status} />
        </aside>
      </div>
    </div>
  );
}

function testMessageFailure(error: ApiError | null): ChatResult | null {
  if (!error || typeof error.body !== "object" || error.body === null) return null;
  const result = (error.body as { test_message?: ChatResult }).test_message;
  return result ?? null;
}
