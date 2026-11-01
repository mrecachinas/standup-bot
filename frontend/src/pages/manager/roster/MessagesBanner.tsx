import { Banner } from "@primer/react";

export interface MessagesBannerProps {
  title: string;
  messages: string[];
  onDismiss?: () => void;
  variant?: "critical" | "warning";
}

/** A Banner listing several messages (ErrorBanner takes a single error). Renders nothing when empty. */
export function MessagesBanner({ title, messages, onDismiss, variant = "critical" }: MessagesBannerProps) {
  if (messages.length === 0) return null;
  return (
    <Banner
      variant={variant}
      title={title}
      description={
        messages.length === 1 ? (
          messages[0]
        ) : (
          <ul style={{ margin: 0, paddingLeft: "var(--base-size-16)" }}>
            {messages.map((message) => (
              <li key={message}>{message}</li>
            ))}
          </ul>
        )
      }
      onDismiss={onDismiss}
    />
  );
}
