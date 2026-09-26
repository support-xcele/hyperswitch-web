// The payment element lives in a cross-origin iframe. Its host can report the
// part of that iframe the buyer can currently see while the page scrolls.
let visibleViewport = null;

if (typeof window !== "undefined") {
  window.addEventListener("message", (event) => {
    const data = event.data;
    if (
      event.source !== window.parent ||
      data?.type !== "getmypics:visible-payment-viewport" ||
      !Number.isFinite(data.top) ||
      !Number.isFinite(data.bottom) ||
      data.top < 0 ||
      data.bottom <= data.top
    ) return;
    visibleViewport = { top: data.top, bottom: data.bottom, receivedAt: Date.now() };
  });
}

export function getMenuLayout(trigger) {
  const rect = trigger?.getBoundingClientRect();
  const viewport = visibleViewport && Date.now() - visibleViewport.receivedAt < 10000
    ? visibleViewport
    : { top: 0, bottom: window.innerHeight };
  const above = Math.max(0, (rect?.top ?? 0) - viewport.top - 6);
  const below = Math.max(0, viewport.bottom - (rect?.bottom ?? 0) - 6);
  const desiredHeight = 304; // Search input, four visible options, and panel padding.
  const openUp = below < desiredHeight && (above >= desiredHeight || above > below);
  const space = openUp ? above : below;
  // Keep the searchable list within the visible part of the host page. When
  // space is tight, the list scrolls while the search input stays in view.
  const listMaxHeight = `${Math.max(48, Math.min(240, Math.floor(space - 62)))}px`;
  return { openUp, listMaxHeight };
}
