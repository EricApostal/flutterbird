// The checks every test page makes, whatever its headers are.
contentChecks([
  "start-root", "start-before-dom", "start-append", "start-observer", "start-domcontentloaded",
  "start-message", "start-storage", "start-import", "start-fetch-own-file",
  "idle-message-async-reply", "idle-port", "idle-tabs-send-message", "idle-tabs-execute-script",
  "idle-tabs-insert-css", "idle-wrapped-js-object", "idle-isolated", "idle-i18n",
  "inject-script-src", "inject-inner-html", "inject-shadow-iframe", "start-fetch-private-file",
  "idle-eval", "idle-reach-into-frame", "idle-who-am-i",
]);
eventually("start-before-page-scripts", () =>
  window.earlySeenByPage === "yes" ? null : "the page's first script ran before document_start content scripts");
eventually("start-css-applies", () =>
  getComputedStyle(document.getElementById("startstyled")).marginLeft === "7px" ? null : "no effect");
eventually("content-script-css", () => {
  const color = getComputedStyle(document.getElementById("csstarget")).color;
  return color === "rgb(1, 2, 3)" ? null : "the colour was " + color;
});
eventually("main-world-script", () => (window.__mainWorldRan === true ? null : "never ran in the page's world"));
eventually("isolated-from-page", () => (window.contentOnly === undefined ? null : "the page sees the content script's globals"));
eventually("injected-script-ran-in-page", () =>
  document.documentElement.getAttribute("data-injected-ran") === "yes" ? null : "it did not run");
eventually("page-receives-content-events", () =>
  window.eventFromContent === "hi" ? null : "the page got " + window.eventFromContent);
eventually("frame-same-origin", () =>
  window.frames_["127.0.0.1"] === true ? null : "the all_frames script did not run in it");
eventually("frame-cross-origin", () =>
  window.frames_["localhost"] === true ? null : "the all_frames script did not run in it");

// A blank frame made by the page.
document.body.appendChild(document.createElement("iframe"));
eventually("frame-about-blank", () => (window.blankFrameRan ? null : "the match_about_blank script did not run"));

// What content scripts may do, the page still may not: its own policies and the
// extension's web_accessible_resources hold for it.
eventually("page-cannot-read-private-files", () => {
  const url = document.documentElement.getAttribute("data-private-file");
  if (!url) return "waiting to be told its address";
  if (window.privateRead === undefined) {
    window.privateRead = "pending";
    fetch(url).then(() => (window.privateRead = "read it"), () => (window.privateRead = "refused"));
  }
  return window.privateRead === "refused" ? null : window.privateRead;
});
