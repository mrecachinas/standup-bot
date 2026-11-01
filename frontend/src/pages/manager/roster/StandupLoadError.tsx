import { Link as RouterLink } from "react-router";
import { Button } from "@primer/react";
import { AlertIcon, LockIcon } from "@primer/octicons-react";
import type { ApiError } from "../../../api/client";
import { EmptyState, ErrorBanner, PageHeader } from "../../../components";
import { paths } from "../../../paths";

/** What a standup tab shows when its first load fails: 403/404 get a friendly empty state. */
export function StandupLoadError({ error, title, onRetry }: { error: ApiError; title: string; onRetry: () => void }) {
  const back = (
    <Button as={RouterLink} to={paths.standups}>
      Back to standups
    </Button>
  );

  if (error.status === 404) {
    return (
      <>
        <PageHeader title={title} />
        <EmptyState icon={AlertIcon} title="Standup not found" description="It may have been deleted, or the link is wrong." action={back} />
      </>
    );
  }

  if (error.status === 403) {
    return (
      <>
        <PageHeader title={title} />
        <EmptyState
          icon={LockIcon}
          title="You don't manage this standup"
          description={error.message || "Ask one of its managers or an admin to add you."}
          action={back}
        />
      </>
    );
  }

  return (
    <>
      <PageHeader title={title} />
      <ErrorBanner error={error} title={`Couldn't load ${title.toLowerCase()}`} action={<Button onClick={onRetry}>Try again</Button>} />
    </>
  );
}
