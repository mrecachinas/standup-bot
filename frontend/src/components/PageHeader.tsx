import type { ReactNode } from "react";
import { Link as RouterLink } from "react-router";
import { Breadcrumbs, PageHeader as PrimerPageHeader } from "@primer/react";

export interface Breadcrumb {
  label: string;
  /** Omit for the current page. */
  to?: string;
}

export interface PageHeaderProps {
  title: ReactNode;
  description?: ReactNode;
  /** Buttons on the right of the title. */
  actions?: ReactNode;
  breadcrumbs?: Breadcrumb[];
  /** Shown right after the title, e.g. a StatusLabel. */
  trailingVisual?: ReactNode;
  /** Extra row under the description (meta items, filters…). */
  children?: ReactNode;
  className?: string;
}

/** Page title block. Pages also call `useDocumentTitle(title)`. */
export function PageHeader({ title, description, actions, breadcrumbs, trailingVisual, children, className }: PageHeaderProps) {
  return (
    <PrimerPageHeader className={className}>
      {breadcrumbs && breadcrumbs.length > 0 && (
        <PrimerPageHeader.ContextArea>
          <PrimerPageHeader.Breadcrumbs>
            <Breadcrumbs>
              {breadcrumbs.map((crumb) =>
                crumb.to ? (
                  <Breadcrumbs.Item key={crumb.label} as={RouterLink} to={crumb.to}>
                    {crumb.label}
                  </Breadcrumbs.Item>
                ) : (
                  <Breadcrumbs.Item key={crumb.label} selected>
                    {crumb.label}
                  </Breadcrumbs.Item>
                ),
              )}
            </Breadcrumbs>
          </PrimerPageHeader.Breadcrumbs>
        </PrimerPageHeader.ContextArea>
      )}
      <PrimerPageHeader.TitleArea>
        <PrimerPageHeader.Title as="h1">{title}</PrimerPageHeader.Title>
        {trailingVisual && <PrimerPageHeader.TrailingVisual>{trailingVisual}</PrimerPageHeader.TrailingVisual>}
      </PrimerPageHeader.TitleArea>
      {actions && <PrimerPageHeader.Actions>{actions}</PrimerPageHeader.Actions>}
      {/* Description is a flex row, so wrap it to keep inline parts (like <time>) flowing as one sentence. */}
      {description && (
        <PrimerPageHeader.Description>
          <span>{description}</span>
        </PrimerPageHeader.Description>
      )}
      {children && <PrimerPageHeader.Navigation as="div">{children}</PrimerPageHeader.Navigation>}
    </PrimerPageHeader>
  );
}
