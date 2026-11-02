import { Link as RouterLink } from "react-router";
import { Button } from "@primer/react";
import { AlertIcon, LockIcon } from "@primer/octicons-react";
import type { ApiError } from "../../../api/client";
import { EmptyState, ErrorBanner, LoadingState, PageHeader } from "../../../components";
import { paths } from "../../../paths";

/** A standup tab before its data arrives: loading, not found, no access, or a retryable error. */
export function StandupLoadState({ error, onRetry, title = "Standup" }: { error: ApiError | null; onRetry: () => void; title?: string }) {
  if (!error) return <LoadingState label={`Loading ${title.toLowerCase()}…`} />;

  const back = (
    <Button as={RouterLink} to={paths.standups}>
      Back to standups
    </Button>
  );

  return (
    <>
      <PageHeader title={title} breadcrumbs={[{ label: "Standups", to: paths.standups }]} />
      {error.status === 404 ? (
        <EmptyState icon={AlertIcon} title="Standup not found" description="It may have been deleted, or the link is wrong." action={back} />
      ) : error.status === 403 ? (
        <EmptyState icon={LockIcon} title="You don't manage this standup" description="Ask one of its managers or an admin to add you." action={back} />
      ) : (
        <ErrorBanner error={error} title="Couldn't load this standup" action={<Button onClick={onRetry}>Try again</Button>} />
      )}
    </>
  );
}
