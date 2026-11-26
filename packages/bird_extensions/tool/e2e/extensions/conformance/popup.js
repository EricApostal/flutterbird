(async () => {
  const server = (await browser.storage.local.get("server")).server;
  const report = (name, failure) =>
    fetch(server + "/report", { method: "POST", body: JSON.stringify({ name, ok: !failure, detail: failure || "" }) });
  async function check(name, run) {
    try {
      await report(name, await run());
    } catch (error) {
      await report(name, "threw " + error);
    }
  }
  await check("popup-message", async () => {
    const reply = await browser.runtime.sendMessage({ kind: "echo", value: 1 });
    return reply && reply.value === 2 ? null : "reply was " + JSON.stringify(reply);
  });
  await check("popup-port", () => new Promise((resolve) => {
    const port = browser.runtime.connect({ name: "conformance" });
    port.onMessage.addListener((message) => resolve(message.pong === "ping" ? null : "wrong reply"));
    port.onDisconnect.addListener(() => resolve("the port closed with no reply"));
    port.postMessage({ ping: "ping" });
    setTimeout(() => resolve("no reply on the port"), 4000);
  }));
  await check("popup-replace-state", () => {
    const url = new URL(location.href);
    url.searchParams.set("context", "popup");
    history.replaceState(null, "", url.href);
    return location.search === "?context=popup" ? null : "the address was " + location.href;
  });
  await check("popup-tabs-query", async () => {
    const tabs = await browser.tabs.query({});
    return tabs.some((tab) => (tab.url || "").includes("/page/")) ? null : "no tab with the test page among " + tabs.length;
  });
  // This popup is open in a tab, and Firefox says so to whoever hears from it.
  await check("popup-in-a-tab-has-sender-tab", async () => {
    const sender = await browser.runtime.sendMessage({ kind: "who-am-i" });
    return sender.tab ? null : "no sender.tab";
  });
  await report("popup-done");
})();
