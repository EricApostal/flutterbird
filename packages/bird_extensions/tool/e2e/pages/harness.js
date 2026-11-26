// Says how each check on this page went. The checks of the extension's content
// scripts are read off the root element; the page adds checks of its own, which
// look from the page's side at what the extension did.
(function () {
  const PAGE = document.currentScript.dataset.page;

  const report = (name, failure) =>
    fetch("/report", { method: "POST", body: JSON.stringify({ name: PAGE + ":" + name, ok: !failure, detail: failure || "" }) });
  window.report = report;

  // Waits for something to become true, then says so.
  window.eventually = function (name, probe, timeout = 9000) {
    const started = Date.now();
    (function look() {
      let failure;
      try {
        failure = probe();
      } catch (error) {
        failure = "threw " + error;
      }
      if (!failure) return report(name);
      if (Date.now() - started > timeout) return report(name, String(failure));
      setTimeout(look, 100);
    })();
  };

  window.contentChecks = function (names) {
    for (const name of names) {
      eventually(name, () => {
        const value = document.documentElement.getAttribute("data-c-" + name);
        if (value === "ok") return null;
        return value === null ? "the content script never got this far" : value;
      });
    }
  };
})();
