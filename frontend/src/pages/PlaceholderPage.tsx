import { PageHeader } from "../components/PageHeader";
import { useDocumentTitle } from "../hooks/useDocumentTitle";

/** Temporary page body until the real page lands. */
export function PlaceholderPage({ title, description = "Coming soon" }: { title: string; description?: string }) {
  useDocumentTitle(title);
  return <PageHeader title={title} description={description} />;
}
