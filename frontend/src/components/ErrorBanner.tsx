import type { ReactNode } from "react";
import { Banner } from "@primer/react";
import { errorMessages } from "../lib/errors";

export interface ErrorBannerProps {
  /** An ApiError, Error, message or list of messages; nothing renders when it's empty. */
  error: unknown;
  title?: string;
  /** e.g. a "Try again" button. */
  action?: ReactNode;
  onDismiss?: () => void;
  className?: string;
}

export function ErrorBanner({ error, title = "Something went wrong", action, onDismiss, className }: ErrorBannerProps) {
  const messages = errorMessages(error);
  if (messages.length === 0) return null;

  return (
    <Banner
      className={className}
      variant="critical"
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
      primaryAction={action}
      onDismiss={onDismiss}
    />
  );
}
