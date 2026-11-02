import type { ReactNode } from "react";
import { Navigate, Outlet, useLocation } from "react-router";
import { Button } from "@primer/react";
import { CommentDiscussionIcon } from "@primer/octicons-react";
import { EmptyState } from "../components/EmptyState";
import { NotFoundPage } from "../pages/NotFoundPage";
import { useDocumentTitle } from "../hooks/useDocumentTitle";
import { useSession } from "./context";
import { homePath, PLATFORM_SIGN_IN, signInPath } from "./paths";
import styles from "./guards.module.css";

function useSignInRedirect(): string {
  const location = useLocation();
  return signInPath(`${location.pathname}${location.search}${location.hash}`);
}

/** Manager pages (/manager/*, /admin): needs a signed-in user; `admin` also needs an admin. */
export function RequireUser({ admin = false, children }: { admin?: boolean; children?: ReactNode }) {
  const { bootstrap } = useSession();
  const signIn = useSignInRedirect();

  if (!bootstrap.user) return <Navigate to={signIn} replace />;
  if (admin && !bootstrap.user.admin) return <NotFoundPage />;
  return children ?? <Outlet />;
}

/** Member pages (/me/*): needs a Slack or Microsoft sign-in (a member identity). */
export function RequireMember({ children }: { children?: ReactNode }) {
  const { bootstrap } = useSession();
  const signIn = useSignInRedirect();

  if (!bootstrap.authenticated) return <Navigate to={signIn} replace />;
  if (!bootstrap.member) return <MemberAccountNeeded />;
  return children ?? <Outlet />;
}

/** "/" → /manager/standups for users, /me for members, otherwise the sign-in page. */
export function HomeRedirect() {
  const { bootstrap } = useSession();
  return <Navigate to={homePath(bootstrap)} replace />;
}

/** Signed in (say, with an access token) but not as a Slack or Teams person, so there are no check-ins to show. */
function MemberAccountNeeded() {
  useDocumentTitle("My standups");
  const platforms = useSession().bootstrap.platforms.filter((platform) => platform.sign_in_enabled);
  const names = platforms.map((platform) => platform.label).join(" or ");

  return (
    <EmptyState
      icon={CommentDiscussionIcon}
      title="Your check-ins live in your chat account"
      description={
        platforms.length > 0
          ? `You're signed in with an access token, which isn't tied to a ${names} account. Sign in with ${names} to see your standups, responses and availability.`
          : "You're signed in with an access token, which isn't tied to a chat account. Ask an admin to turn on Slack or Microsoft sign-in."
      }
      action={
        platforms.length > 0 && (
          <div className={styles.actions}>
            {platforms.map((platform) => (
              <Button key={platform.key} as="a" href={PLATFORM_SIGN_IN[platform.key].href} variant="primary">
                {PLATFORM_SIGN_IN[platform.key].label}
              </Button>
            ))}
          </div>
        )
      }
    />
  );
}
