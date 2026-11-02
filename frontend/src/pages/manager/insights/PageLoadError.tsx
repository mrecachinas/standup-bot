import { Link as RouterLink } from "react-router";
import { Button } from "@primer/react";
import { LockIcon, QuestionIcon, SyncIcon } from "@primer/octicons-react";
import type { ApiError } from "../../../api/client";
import { EmptyState, ErrorBanner } from "../../../components";
import { paths } from "../../../paths";

export interface PageLoadErrorProps {
  error: ApiError;
  onRetry?: () => void;
  /** What failed to load, for the 404/403 copy (default "standup"). */
  thing?: string;
  backTo?: { label: string; to: string };
}

/** A page's initial load failed: not found, forbidden, or something else (with "Try again"). */
export function PageLoadError({ error, onRetry, thing = "standup", backTo = { label: "Back to standups", to: paths.standups } }: PageLoadErrorProps) {
  const back = (
    <Button as={RouterLink} to={backTo.to}>
      {backTo.label}
    </Button>
  );

  if (error.status === 404) {
    return <EmptyState icon={QuestionIcon} title={`${capitalize(thing)} not found`} description={`That ${thing} doesn't exist, or it was deleted.`} action={back} />;
  }
  if (error.status === 403) {
    return <EmptyState icon={LockIcon} title={`You don't have access to this ${thing}`} description={error.message} action={back} />;
  }

  return (
    <ErrorBanner
      error={error}
      title={`Couldn't load this ${thing}`}
      action={
        onRetry && (
          <Button leadingVisual={SyncIcon} onClick={onRetry}>
            Try again
          </Button>
        )
      }
    />
  );
}

function capitalize(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}
