import { Link as RouterLink } from "react-router";
import { Button } from "@primer/react";
import { AlertIcon, LockIcon } from "@primer/octicons-react";
import type { ApiError } from "../../../api/client";
import { EmptyState, ErrorBanner, PageHeader } from "../../../components";
import { paths } from "../../../paths";

/** What a standup page shows when its data can't load: not found, no access, or a retryable error. */
export function StandupLoadError({ error, onRetry, title = "Standup" }: { error: ApiError; onRetry?: () => void; title?: string }) {
  const back = (
    <Button as={RouterLink} to={paths.standups}>
      Back to standups
    </Button>
  );

  if (error.status === 404) {
    return (
      <>
        <PageHeader title={title} breadcrumbs={[{ label: "Standups", to: paths.standups }]} />
        <EmptyState icon={AlertIcon} title="Standup not found" description="It may have been deleted, or the link is wrong." action={back} />
      </>
    );
  }

  if (error.status === 403) {
    return (
      <>
        <PageHeader title={title} breadcrumbs={[{ label: "Standups", to: paths.standups }]} />
        <EmptyState icon={LockIcon} title="You don't manage this standup" description="Ask one of its managers or an admin to add you." action={back} />
      </>
    );
  }

  return (
    <>
      <PageHeader title={title} breadcrumbs={[{ label: "Standups", to: paths.standups }]} />
      <ErrorBanner
        error={error}
        title="Couldn't load this standup"
        action={onRetry ? <Button onClick={onRetry}>Try again</Button> : undefined}
      />
    </>
  );
}
