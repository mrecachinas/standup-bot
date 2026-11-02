import { Banner, Button } from "@primer/react";
import { PaperAirplaneIcon } from "@primer/octicons-react";
import { ApiError, post } from "../../../api/client";
import type { ChatResult, ChatSetupPayload } from "../../../api/types/chat";
import { useMutation } from "../../../hooks/useMutation";
import { Section } from "../standups/Section";
import styles from "./SettingsLayout.module.css";

/** Posts a test message to the standup's channel, so a manager can check the bot can reach it. */
export function TestMessagePanel({ standupId, platformLabel }: { standupId: number; platformLabel: string }) {
  const send = useMutation(() => post<ChatSetupPayload>(`/api/standups/${standupId}/chat_setup/test_message`));
  const failure = failureFrom(send.error);

  return (
    <Section title="Test message" hint={`Check the bot can post to this standup's ${platformLabel} channel.`}>
      <div className={styles.panelBody}>
        {send.error && (
          <Banner
            variant="warning"
            title="Test message failed"
            description={
              <div className={styles.failure}>
                <p>{failure?.message ?? send.error.message}</p>
                {failure?.action && <p>Next step: {failure.action}</p>}
              </div>
            }
            onDismiss={send.reset}
          />
        )}
        <Button type="button" leadingVisual={PaperAirplaneIcon} onClick={() => void send.run()} loading={send.loading} block>
          Send test message
        </Button>
      </div>
    </Section>
  );
}

function failureFrom(error: ApiError | null): ChatResult | null {
  if (!error || typeof error.body !== "object" || error.body === null) return null;
  return (error.body as { test_message?: ChatResult }).test_message ?? null;
}
