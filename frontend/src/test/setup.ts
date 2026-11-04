import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";
import { configureSessionHooks, setCsrfToken } from "../api/client";

// jsdom lacks a few browser APIs Primer React relies on.
if (!window.matchMedia) {
  Object.defineProperty(window, "matchMedia", {
    writable: true,
    value: (query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }),
  });
}

class NoopObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() {
    return [];
  }
}

globalThis.ResizeObserver ??= NoopObserver as unknown as typeof ResizeObserver;
globalThis.IntersectionObserver ??= NoopObserver as unknown as typeof IntersectionObserver;

if (!HTMLElement.prototype.scrollIntoView) HTMLElement.prototype.scrollIntoView = () => {};
window.scrollTo = () => {};

// jsdom has no Popover API, and the polyfill Primer's tooltips load needs
// adoptedStyleSheets (also missing). A no-op popover API keeps it from loading.
if (!("popover" in HTMLElement.prototype)) {
  const proto = HTMLElement.prototype as unknown as Record<string, unknown>;
  Object.defineProperty(proto, "popover", {
    configurable: true,
    get(this: HTMLElement) {
      return this.getAttribute("popover");
    },
    set(this: HTMLElement, value: string | null) {
      if (value === null) this.removeAttribute("popover");
      else this.setAttribute("popover", value);
    },
  });
  proto.showPopover = () => {};
  proto.hidePopover = () => {};
  proto.togglePopover = () => false;
}

// Primer's Autocomplete announces results through a <live-region> element,
// which the Node build Vitest loads doesn't register with jsdom.
if (!customElements.get("live-region")) {
  customElements.define(
    "live-region",
    class extends HTMLElement {
      announce() {
        return { cancel() {} };
      }
      announceFromElement() {
        return { cancel() {} };
      }
    },
  );
}

afterEach(() => {
  cleanup();
  window.localStorage.clear();
  setCsrfToken(null);
  configureSessionHooks({});
  vi.unstubAllGlobals();
});
