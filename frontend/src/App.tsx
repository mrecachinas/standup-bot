import { useState } from "react";
import { RouterProvider } from "react-router/dom";
import { createRouter } from "./router";
import { ThemeRoot } from "./theme/ThemeRoot";

type AppRouter = ReturnType<typeof createRouter>;

export function App({ router: providedRouter }: { router?: AppRouter }) {
  const [router] = useState(() => providedRouter ?? createRouter());
  return (
    <ThemeRoot>
      <RouterProvider router={router} />
    </ThemeRoot>
  );
}
