import { Outlet, ScrollRestoration } from "react-router";
import { FlashProvider } from "../flash/FlashProvider";
import { FlashRegion } from "../flash/FlashRegion";
import { SessionProvider } from "../session/SessionProvider";

/** Top-level route element: flash store, session bootstrap and toasts around every page. */
export function Root() {
  return (
    <FlashProvider>
      <SessionProvider>
        <Outlet />
        <FlashRegion />
        <ScrollRestoration />
      </SessionProvider>
    </FlashProvider>
  );
}
