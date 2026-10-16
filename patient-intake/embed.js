(() => {
  const script = document.currentScript;
  if (!script) return;
  const assetOrigin = new URL(script.src, window.location.href).origin;
  const frames = new Map();
  document.querySelectorAll("[data-customer-flow-form]").forEach((container, index) => {
    const key = container.dataset.customerFlowForm;
    if (!/^[A-Za-z0-9_-]{24,96}$/.test(key || "")) return;
    const frame = document.createElement("iframe");
    frame.src = `${assetOrigin}/embed/${encodeURIComponent(key)}`;
    frame.title = container.dataset.title || "Hair transplant consultation form";
    frame.loading = index === 0 ? "eager" : "lazy";
    frame.allow = "camera";
    frame.style.width = "100%";
    frame.style.height = "850px";
    frame.style.border = "0";
    frame.style.display = "block";
    container.replaceChildren(frame);
    frames.set(frame.contentWindow, frame);
  });
  window.addEventListener("message", (event) => {
    if (event.origin !== assetOrigin || event.data?.type !== "customer-flow:resize") return;
    const frame = frames.get(event.source);
    const height = Number(event.data.height);
    if (frame && Number.isFinite(height)) frame.style.height = `${Math.min(Math.max(height, 520), 2400)}px`;
  });
})();
