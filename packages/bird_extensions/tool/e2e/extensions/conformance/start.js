// Runs at document_start. Each check leaves "ok" or what went wrong on the
// root element, where the page looks for it.
(() => {
  const rootAtStart = document.documentElement;
  const pending = [];
  function mark(name, value) {
    const root = document.documentElement;
    if (root) root.setAttribute("data-c-" + name, value);
    else pending.push([name, value]);
  }
  if (!rootAtStart) {
    const timer = setInterval(() => {
      if (!document.documentElement) return;
      clearInterval(timer);
      for (const [name, value] of pending) mark(name, value);
    }, 5);
  }
  async function check(name, run) {
    try {
      const failure = await run();
      mark(name, failure ? String(failure) : "ok");
    } catch (error) {
      mark(name, "threw " + error);
    }
  }

  check("start-root", () => (rootAtStart ? null : "document.documentElement was null"));
  // The page's first script reads this, so it must be there before any runs.
  try {
    document.documentElement.setAttribute("data-c-early", "yes");
  } catch (_) {}
  check("start-before-dom", () => (document.body ? "the body had been parsed" : null));
  check("start-append", () => {
    const style = document.createElement("style");
    style.textContent = "#startstyled { margin-left: 7px }";
    (document.head || document.documentElement).appendChild(style);
  });
  check("start-observer", () => new Promise((resolve) => {
    const observer = new MutationObserver(() => {
      if (document.getElementById("parsed-late")) {
        observer.disconnect();
        resolve(null);
      }
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => resolve("never saw what the parser added"), 4000);
  }));
  check("start-domcontentloaded", () => new Promise((resolve) => {
    if (document.readyState !== "loading") return resolve("it had already fired");
    document.addEventListener("DOMContentLoaded", () => resolve(null), { once: true });
    setTimeout(() => resolve("never fired"), 4000);
  }));
  check("start-message", async () => {
    const reply = await browser.runtime.sendMessage({ kind: "echo", value: 41 });
    return reply && reply.value === 42 ? null : "reply was " + JSON.stringify(reply);
  });
  check("start-storage", async () => {
    await browser.storage.local.set({ fromContent: { n: 1 } });
    const got = await browser.storage.local.get("fromContent");
    return got.fromContent && got.fromContent.n === 1 ? null : "read back " + JSON.stringify(got);
  });
  check("start-import", async () => {
    const module = await import(browser.runtime.getURL("module.js"));
    return module.answer === 42 ? null : "the module said " + module.answer;
  });
  // Only the extension's own scripts may read a file it did not make web
  // accessible. The page is told where it is, and must not be able to.
  check("start-fetch-private-file", async () => {
    const url = browser.runtime.getURL("private.json");
    const text = await (await fetch(url)).text();
    document.documentElement.setAttribute("data-private-file", url);
    return text.includes("secret") ? null : "unexpected contents";
  });
  check("start-fetch-own-file", async () => {
    const text = await (await fetch(browser.runtime.getURL("module.js"))).text();
    return text.includes("answer") ? null : "unexpected contents";
  });
})();
