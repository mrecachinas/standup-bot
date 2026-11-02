import { Button } from "@primer/react";
import { useSearchParams } from "react-router";
import type { PlatformKey } from "../../api/types";
import type { StandupFormPayload } from "../../api/types/standups";
import { ErrorBanner, LoadingState, PageHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useForwardedQuery } from "../../hooks/useForwardedQuery";
import { paths } from "../../paths";
import { StandupForm } from "./standupForm/StandupForm";
import { TemplatePicker } from "./standupForm/TemplatePicker";
import layout from "../../styles/layout.module.css";

/** /manager/standups/new?template=&platform=: pick a template, then fill in the editor. */
export function NewStandupPage() {
  useDocumentTitle("New standup");
  const [, setSearchParams] = useSearchParams();
  const { data, error, loading, reload } = useApi<StandupFormPayload>(useForwardedQuery("/api/standups/new", ["template", "platform"]));

  const hrefFor = (template: string) => {
    const params = new URLSearchParams({ template });
    if (data?.show_platform_picker) params.set("platform", data.platform.key);
    return `${paths.newStandup}?${params.toString()}`;
  };

  const changePlatform = (platform: PlatformKey) => {
    const params = new URLSearchParams({ platform });
    if (data?.template_key) params.set("template", data.template_key);
    setSearchParams(params, { replace: true });
  };

  return (
    <div className={layout.page}>
      <PageHeader
        title="Create a standup"
        description="Start from a template or from scratch. You can change everything later."
        breadcrumbs={[{ label: "Standups", to: paths.standups }, { label: "New" }]}
      />

      {!data && loading && <LoadingState label="Loading the editor…" />}
      {error && <ErrorBanner error={error} title="Couldn't load the editor" action={<Button onClick={reload}>Try again</Button>} />}

      {data && (
        <>
          <TemplatePicker templates={data.templates} selected={data.template_key} hrefFor={hrefFor} />
          <StandupForm key={`${data.template_key}:${data.platform.key}`} payload={data} onPlatformChange={changePlatform} />
        </>
      )}
    </div>
  );
}
