import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App, RootErrorBoundary } from "./App";
import { assertSafeRouteManifest } from "./routes";

assertSafeRouteManifest();

const container = document.getElementById("practice-root");
if (!container) throw new Error("Practice portal root is unavailable");

createRoot(container).render(
  <StrictMode>
    <RootErrorBoundary>
      <App />
    </RootErrorBoundary>
  </StrictMode>,
);
