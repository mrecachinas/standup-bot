import { useState, type FormEvent } from "react";
import { Navigate, useNavigate, useSearchParams } from "react-router";
import { Button, FormControl, TextInput } from "@primer/react";
import { CommentDiscussionIcon, HashIcon, PeopleIcon } from "@primer/octicons-react";
import { ApiError } from "../../api/client";
import { ErrorBanner } from "../../components/ErrorBanner";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useSession } from "../../session/context";
import { canAccess, PLATFORM_SIGN_IN, safeNextPath } from "../../session/paths";
import styles from "./SignInPage.module.css";

export function SignInPage() {
  useDocumentTitle("Sign in");
  const { bootstrap, signIn } = useSession();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const next = safeNextPath(searchParams.get("next"));

  const prefill = bootstrap.dev_prefill;
  const [email, setEmail] = useState(prefill?.email ?? "");
  const [accessToken, setAccessToken] = useState(prefill?.access_token ?? "");
  const [error, setError] = useState<ApiError | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [tokenFormOpen, setTokenFormOpen] = useState(Boolean(prefill));

  const platforms = bootstrap.platforms.filter((platform) => platform.sign_in_enabled);

  // Signed in already: go on, unless they came here to reach a page their
  // current identity can't open (e.g. a member signing in as a manager).
  if (!submitting && bootstrap.authenticated && (!next || canAccess(bootstrap, next))) {
    return <Navigate to={next ?? "/"} replace />;
  }

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await signIn({ email: email.trim(), access_token: accessToken });
      navigate(next ?? "/", { replace: true });
    } catch (caught) {
      setError(caught instanceof ApiError ? caught : new ApiError(0, undefined));
      setTokenFormOpen(true);
      setSubmitting(false);
    }
  };

  const form = (
    <form className={styles.form} onSubmit={handleSubmit} noValidate>
      <FormControl required>
        <FormControl.Label>Email</FormControl.Label>
        <TextInput type="email" name="email" autoComplete="username" value={email} onChange={(event) => setEmail(event.target.value)} block />
      </FormControl>
      <FormControl required>
        <FormControl.Label>Access token</FormControl.Label>
        <TextInput
          type="password"
          name="access_token"
          autoComplete="current-password"
          value={accessToken}
          onChange={(event) => setAccessToken(event.target.value)}
          block
        />
      </FormControl>
      <Button type="submit" variant={platforms.length > 0 ? "default" : "primary"} loading={submitting} block>
        Sign in
      </Button>
    </form>
  );

  return (
    <main className={styles.page} id="main">
      <div className={styles.card}>
        <div className={styles.brand}>
          <span className={styles.brandMark} aria-hidden="true">
            <CommentDiscussionIcon size={24} />
          </span>
          <h1 className={styles.title}>Sign in to Standup Bot</h1>
        </div>

        <ErrorBanner error={error} title="Couldn't sign in" />

        {platforms.length > 0 && (
          <div className={styles.buttons}>
            {platforms.map((platform, index) => {
              const link = PLATFORM_SIGN_IN[platform.key];
              return (
                <Button
                  key={platform.key}
                  as="a"
                  href={link.href}
                  variant={index === 0 ? "primary" : "default"}
                  leadingVisual={platform.icon === "people" ? PeopleIcon : HashIcon}
                  size="large"
                  block
                >
                  {link.label}
                </Button>
              );
            })}
          </div>
        )}

        {platforms.length > 0 ? (
          <details className={styles.details} open={tokenFormOpen} onToggle={(event) => setTokenFormOpen(event.currentTarget.open)}>
            <summary>Sign in with an access token instead</summary>
            {form}
          </details>
        ) : (
          form
        )}
      </div>
      <p className={styles.footer}>Async standups for Slack and Microsoft Teams.</p>
    </main>
  );
}
