import { Link as RouterLink, matchPath, useLocation } from "react-router";
import { IconButton, NavList } from "@primer/react";
import {
  AppsIcon,
  CalendarIcon,
  CommentDiscussionIcon,
  InboxIcon,
  PlugIcon,
  PlusIcon,
  ShieldIcon,
  SignOutIcon,
} from "@primer/octicons-react";
import { Avatar } from "../components/Avatar";
import { useFlash } from "../flash/context";
import { useSession } from "../session/context";
import { ThemeSwitch } from "../theme/ThemeSwitch";
import { paths } from "../paths";
import styles from "./AppShell.module.css";

function current(isCurrent: boolean): "page" | undefined {
  return isCurrent ? "page" : undefined;
}

export function Sidebar() {
  const { bootstrap, signOut } = useSession();
  const { push } = useFlash();
  const { pathname } = useLocation();
  const { user, member } = bootstrap;
  const standupMatch = matchPath("/manager/standups/:id/*", pathname);
  const currentStandupId = standupMatch?.params.id;
  const displayName = user?.name ?? member?.name ?? "";

  const handleSignOut = () => {
    signOut().catch(() => push({ type: "danger", message: "Couldn't sign out. Try again." }));
  };

  return (
    <div className={styles.sidebar}>
      <RouterLink to={user ? paths.standups : paths.me} className={styles.brand}>
        <span className={styles.brandMark} aria-hidden="true">
          <CommentDiscussionIcon size={16} />
        </span>
        <span>Standup Bot</span>
      </RouterLink>

      {member && (
        <NavList aria-label="Me">
          {user ? (
            <NavList.Group title="You">
              <MemberItems pathname={pathname} />
            </NavList.Group>
          ) : (
            <MemberItems pathname={pathname} />
          )}
        </NavList>
      )}

      {user && (
        <NavList aria-label="Main">
          <NavList.Item as={RouterLink} to={paths.standups} aria-current={current(pathname === paths.standups)}>
            <NavList.LeadingVisual>
              <AppsIcon />
            </NavList.LeadingVisual>
            Overview
          </NavList.Item>
          <NavList.Item as={RouterLink} to={paths.integrations} aria-current={current(pathname.startsWith(paths.integrations))}>
            <NavList.LeadingVisual>
              <PlugIcon />
            </NavList.LeadingVisual>
            Integrations
          </NavList.Item>
          {user.admin && (
            <NavList.Item as={RouterLink} to={paths.admin} aria-current={current(pathname === paths.admin || pathname.startsWith(`${paths.admin}/`))}>
              <NavList.LeadingVisual>
                <ShieldIcon />
              </NavList.LeadingVisual>
              Admin
            </NavList.Item>
          )}
        </NavList>
      )}

      {user && (
        <section aria-labelledby="sidebar-standups-heading">
          <div className={styles.sectionHeader}>
            <h2 id="sidebar-standups-heading" className={styles.sectionTitle}>
              Standups
            </h2>
            <IconButton as={RouterLink} to={paths.newStandup} icon={PlusIcon} aria-label="New standup" size="small" variant="invisible" />
          </div>
          {bootstrap.sidebar_standups.length > 0 ? (
            <NavList aria-labelledby="sidebar-standups-heading">
              {bootstrap.sidebar_standups.map((standup) => (
                <NavList.Item
                  key={standup.id}
                  as={RouterLink}
                  to={paths.standup(standup.id)}
                  aria-current={current(currentStandupId === String(standup.id))}
                >
                  <NavList.LeadingVisual>
                    <span
                      className={`${styles.dot} ${standup.active ? styles.dotActive : styles.dotPaused}`}
                      role="img"
                      aria-label={standup.active ? "Active" : "Paused"}
                      title={standup.active ? "Active" : "Paused"}
                    />
                  </NavList.LeadingVisual>
                  {standup.name}
                </NavList.Item>
              ))}
            </NavList>
          ) : (
            <p className={styles.empty}>No standups yet</p>
          )}
        </section>
      )}

      <div className={styles.footer}>
        <ThemeSwitch />
        <div className={styles.user}>
          <Avatar name={displayName} src={user?.avatar_url ?? member?.avatar_url} size={32} />
          <div className={styles.userMeta}>
            <div className={styles.userName}>{displayName}</div>
            <div className={styles.userRole}>{user?.admin ? "Admin" : "Member"}</div>
          </div>
          <IconButton icon={SignOutIcon} aria-label="Sign out" variant="invisible" size="small" onClick={handleSignOut} />
        </div>
      </div>
    </div>
  );
}

function MemberItems({ pathname }: { pathname: string }) {
  return (
    <>
      <NavList.Item as={RouterLink} to={paths.me} aria-current={current(pathname === paths.me)}>
        <NavList.LeadingVisual>
          <CommentDiscussionIcon />
        </NavList.LeadingVisual>
        My standups
      </NavList.Item>
      <NavList.Item as={RouterLink} to={paths.myResponses} aria-current={current(pathname.startsWith(paths.myResponses))}>
        <NavList.LeadingVisual>
          <InboxIcon />
        </NavList.LeadingVisual>
        My responses
      </NavList.Item>
      <NavList.Item as={RouterLink} to={paths.availability} aria-current={current(pathname.startsWith(paths.availability))}>
        <NavList.LeadingVisual>
          <CalendarIcon />
        </NavList.LeadingVisual>
        Availability
      </NavList.Item>
    </>
  );
}
