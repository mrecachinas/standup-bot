import type { ReactNode } from "react";
import { Navigate, Outlet, useLocation } from "react-router";
import { Button } from "@primer/react";
import { EmptyState } from "../components/EmptyState";
import { NotFoundPage } from "../pages/NotFoundPage";
import { useDocumentTitle } from "../hooks/useDocumentTitle";
import { useSession } from "./context";
import { homePath, signInPath } from "./paths";

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
  if (!bootstrap.member) return <MemberSignInNeeded signInHref={signIn} />;
  return children ?? <Outlet />;
}

/** "/" → /manager/standups for users, /me for members, otherwise the sign-in page. */
export function HomeRedirect() {
  const { bootstrap } = useSession();
  return <Navigate to={homePath(bootstrap)} replace />;
}

function MemberSignInNeeded({ signInHref }: { signInHref: string }) {
  useDocumentTitle("Sign in to see your standups");
  const platforms = useSession().bootstrap.platforms.filter((platform) => platform.sign_in_enabled);
  const names = platforms.map((platform) => platform.label).join(" or ") || "your chat account";

  return (
    <EmptyState
      title="Sign in to see your standups"
      description={`Your standups, responses and availability show up once you sign in with ${names}.`}
      action={
        <Button as="a" href={signInHref} variant="primary">
          Go to sign in
        </Button>
      }
    />
  );
}
