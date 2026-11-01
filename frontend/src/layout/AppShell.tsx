import { Outlet } from "react-router";
import { PageLayout } from "@primer/react";
import { useSession } from "../session/context";
import { Sidebar } from "./Sidebar";
import styles from "./AppShell.module.css";

/** Sidebar + main content for signed-in pages. Signed-out visitors just get the content. */
export function AppShell() {
  const { bootstrap } = useSession();

  if (!bootstrap.authenticated) {
    return (
      <main className={`${styles.content} ${styles.signedOut}`} id="main">
        <Outlet />
      </main>
    );
  }

  return (
    <PageLayout padding="none" rowGap="none" columnGap="none">
      <PageLayout.Pane position="start" width="small" divider="line" sticky aria-label="Primary" padding="none">
        <Sidebar />
      </PageLayout.Pane>
      <PageLayout.Content as="main" width="full" padding="none" className={styles.content}>
        <Outlet />
      </PageLayout.Content>
    </PageLayout>
  );
}
