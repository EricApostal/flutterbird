// The server address arrives in the first message a page sends, since only the
// test knows it. Until then it is read from storage.
let server = null;
let overlayLoaded = false;
const committed = new Set();
const completed = new Set();

async function report(name, failure) {
  if (!server) server = (await browser.storage.local.get("server")).server;
  await fetch(server + "/report", { method: "POST", body: JSON.stringify({ name, ok: !failure, detail: failure || "" }) });
}

browser.webRequest.onBeforeRequest.addListener(
  (details) => {
    if (details.url.includes("blocked")) return { cancel: true };
    if (details.url.includes("redirect-me")) return { redirectUrl: details.url.replace("redirect-me", "redirected") };
    return {};
  },
  { urls: ["*://127.0.0.1/net/*"] },
  ["blocking"],
);
browser.webRequest.onBeforeSendHeaders.addListener(
  (details) => ({ requestHeaders: [...details.requestHeaders, { name: "X-Bird-Added", value: "yes" }] }),
  { urls: ["*://127.0.0.1/net/headers*"] },
  ["blocking", "requestHeaders"],
);
browser.webRequest.onHeadersReceived.addListener(
  (details) => ({ responseHeaders: [...details.responseHeaders, { name: "Content-Security-Policy", value: "img-src 'none'" }] }),
  { urls: ["*://127.0.0.1/page/response-headers*"], types: ["main_frame"] },
  ["blocking", "responseHeaders"],
);

browser.webNavigation.onCommitted.addListener((details) => {
  if (details.frameId === 0) committed.add(details.url);
});
browser.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (change.status === "complete") completed.add(tab.url);
});

browser.runtime.onConnect.addListener((port) => {
  port.onMessage.addListener((message) => port.postMessage({ pong: message.ping }));
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message.kind) {
    case "echo":
      return Promise.resolve({ value: message.value + 1 });
    case "later":
      setTimeout(() => sendResponse("later reply"), 100);
      return true;
    case "message-me-back":
      return browser.tabs
        .sendMessage(sender.tab.id, { kind: "from-background" })
        .then((reply) => (reply && reply.title ? "ok" : "reply was " + JSON.stringify(reply)), (e) => "threw " + e);
    case "run-in-my-tab":
      return browser.tabs
        .executeScript(sender.tab.id, { code: "document.title" })
        .then((r) => (r && typeof r[0] === "string" ? "ok" : "returned " + JSON.stringify(r)), (e) => "threw " + e);
    case "style-my-tab":
      return browser.tabs
        .insertCSS(sender.tab.id, { code: "#inserted { width: 123px !important }" })
        .then(() => "ok", (e) => "threw " + e);
    case "overlay-ran":
      overlayLoaded = true;
      return undefined;
    case "overlay-loaded?":
      return Promise.resolve(overlayLoaded);
    case "who-am-i":
      return Promise.resolve({ url: sender.url, tab: sender.tab ? { id: sender.tab.id } : null });
    case "navigation-events":
      return Promise.resolve({ committed: committed.has(message.url), completed: completed.has(message.url) });
    default:
      return undefined;
  }
});

// Lets the test hand over its address, then says the background page is up.
(async () => {
  const configured = await (await fetch(browser.runtime.getURL("config.json"))).json();
  server = configured.server;
  await browser.storage.local.set({ server });
  await report("background-loaded");

  // IndexedDB has to outlive the browser: the second run finds what the first
  // one wrote.
  const database = await new Promise((resolve, reject) => {
    const open = indexedDB.open("conformance", 1);
    open.onupgradeneeded = () => {
      const store = open.result.createObjectStore("items", { keyPath: "id", autoIncrement: true });
      store.createIndex("by-name", "name", { unique: true });
    };
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
  const read = (request) => new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const items = () => database.transaction("items", "readwrite").objectStore("items");
  const found = await read(items().index("by-name").get("kept"));
  if (!found) {
    const key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
    const iv = new Uint8Array(12);
    const secret = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode("sesame"));
    await read(items().put({ name: "kept", key, iv, secret, when: new Date(0), blob: new Blob(["blob text"]) }));
    await report("idb-first-run-wrote");
  } else {
    let failure = null;
    try {
      const plain = new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: found.iv }, found.key, found.secret));
      if (plain !== "sesame") failure = "decrypted " + plain;
      else if ((await found.blob.text()) !== "blob text") failure = "the blob changed";
      else if (found.when.getTime() !== 0) failure = "the date changed";
      const next = await read(items().add({ name: "second" }));
      if (!failure && next <= found.id) failure = "the key generator started over: " + next;
    } catch (error) {
      failure = "threw " + error;
    }
    await report("idb-survived-restart", failure);
  }
})().catch((error) => report("background-loaded", "threw " + error));
