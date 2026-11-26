(() => {
  const mark = (name, value) => document.documentElement.setAttribute("data-c-" + name, value);
  async function check(name, run) {
    try {
      const failure = await run();
      mark(name, failure ? String(failure) : "ok");
    } catch (error) {
      mark(name, "threw " + error);
    }
  }
  window.contentOnly = "secret";

  check("idle-message-async-reply", async () => {
    const reply = await browser.runtime.sendMessage({ kind: "later" });
    return reply === "later reply" ? null : "reply was " + JSON.stringify(reply);
  });
  check("idle-port", () => new Promise((resolve) => {
    const port = browser.runtime.connect({ name: "conformance" });
    port.onMessage.addListener((message) => {
      port.disconnect();
      resolve(message.pong === "ping" ? null : "got " + JSON.stringify(message));
    });
    port.onDisconnect.addListener(() => resolve("the port closed with no reply"));
    port.postMessage({ ping: "ping" });
    setTimeout(() => resolve("no reply on the port"), 4000);
  }));

  browser.runtime.onMessage.addListener((message) => {
    if (message.kind === "from-background") {
      return Promise.resolve({ title: document.title });
    }
    return undefined;
  });
  check("idle-tabs-send-message", async () => {
    const result = await browser.runtime.sendMessage({ kind: "message-me-back" });
    return result === "ok" ? null : result;
  });
  check("idle-tabs-execute-script", async () => {
    const result = await browser.runtime.sendMessage({ kind: "run-in-my-tab" });
    return result === "ok" ? null : result;
  });
  check("idle-tabs-insert-css", async () => {
    const result = await browser.runtime.sendMessage({ kind: "style-my-tab" });
    if (result !== "ok") return result;
    await new Promise((resolve) => setTimeout(resolve, 200));
    const width = getComputedStyle(document.getElementById("inserted")).width;
    return width === "123px" ? null : "the width was " + width;
  });
  check("idle-wrapped-js-object", () =>
    window.wrappedJSObject && window.wrappedJSObject.pageVariable === "from page"
      ? null
      : "the page's variable was not visible");
  check("idle-isolated", () => (typeof window.pageVariable === "undefined" ? null : "page variables leak in"));
  check("idle-i18n", () => {
    const text = browser.i18n.getMessage("greeting", ["there"]);
    return text === "hello there" ? null : "got " + text;
  });
  check("idle-eval", () => {
    const made = new Function("return 6 * 7")();
    return made === 42 && eval("1 + 1") === 2 ? null : "got " + made;
  });
  // Frames are the same document tree, so their windows can be reached.
  check("idle-reach-into-frame", () => new Promise((resolve) => {
    const look = () => {
      const frame = document.querySelector('iframe[src="/frame/same"]');
      if (!frame.contentDocument || frame.contentDocument.title !== "frame") return setTimeout(look, 100);
      if (typeof frame.contentWindow.postMessage !== "function") return resolve("contentWindow has no postMessage");
      if (frame.contentWindow.parent !== window.top && !frame.contentWindow.parent) return resolve("no parent");
      resolve(frame.contentWindow.location.pathname === "/frame/same" ? null : "wrong location");
    };
    look();
    setTimeout(() => resolve("the frame never loaded"), 5000);
  }));
  check("idle-who-am-i", async () => {
    const sender = await browser.runtime.sendMessage({ kind: "who-am-i" });
    return sender.tab && sender.url === location.href ? null : "sender was " + JSON.stringify(sender);
  });
  check("idle-custom-event", () => {
    document.dispatchEvent(new CustomEvent("from-content", { detail: "hi" }));
  });

  // Reaching into the page the way ad blockers and password managers do.
  check("inject-script-src", () => new Promise((resolve) => {
    const script = document.createElement("script");
    script.src = browser.runtime.getURL("injected.js");
    script.onload = () => resolve(null);
    script.onerror = () => resolve("the script failed to load");
    (document.head || document.documentElement).appendChild(script);
    setTimeout(() => resolve("neither load nor error"), 4000);
  }));
  check("inject-inline-script", () => {
    const script = document.createElement("script");
    script.textContent = "document.documentElement.setAttribute('data-inline-ran', 'yes')";
    document.documentElement.appendChild(script);
    script.remove();
  });
  check("inject-inner-html", () => {
    const host = document.createElement("div");
    host.innerHTML = "<span id='from-inner-html'>x</span>";
    document.body.appendChild(host);
    return document.getElementById("from-inner-html") ? null : "no span appeared";
  });
  check("inject-shadow-iframe", () => new Promise((resolve) => {
    const host = document.createElement("div");
    document.body.appendChild(host);
    const frame = document.createElement("iframe");
    frame.src = browser.runtime.getURL("overlay.html");
    host.attachShadow({ mode: "closed" }).appendChild(frame);
    // The overlay tells the background it loaded.
    const deadline = Date.now() + 5000;
    const poll = async () => {
      const loaded = await browser.runtime.sendMessage({ kind: "overlay-loaded?" });
      if (loaded) return resolve(null);
      if (Date.now() > deadline) return resolve("the extension frame never ran");
      setTimeout(poll, 200);
    };
    poll();
  }));
})();
