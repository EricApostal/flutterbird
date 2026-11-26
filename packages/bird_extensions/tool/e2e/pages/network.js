// Requests an extension is to block, redirect or change.
(async () => {
  eventually("webrequest-blocks-parser-script", () =>
    window.parsedBlockedErrored && !window.loaded_blocked_parsed_js ? null : "the script loaded");

  const fails = async (what) => {
    try {
      await what();
      return "the request went through";
    } catch (_) {
      return null;
    }
  };
  report("webrequest-blocks-fetch", await fails(() => fetch("/net/blocked-fetch")));
  report("webrequest-blocks-xhr", await new Promise((resolve) => {
    const request = new XMLHttpRequest();
    request.open("GET", "/net/blocked-xhr");
    request.onload = () => resolve("the request went through");
    request.onerror = () => resolve(null);
    request.send();
  }));
  const element = (tag, url) => new Promise((resolve) => {
    const node = document.createElement(tag);
    node.onload = () => resolve("it loaded");
    node.onerror = () => resolve(null);
    node.src = url;
    document.body.appendChild(node);
    setTimeout(() => resolve("neither load nor error"), 5000);
  });
  report("webrequest-blocks-dynamic-script", await element("script", "/net/blocked-dynamic.js"));
  report("webrequest-blocks-image", await element("img", "/net/blocked-image.png"));

  try {
    const redirected = await (await fetch("/net/redirect-me")).text();
    report("webrequest-redirects", redirected === "redirected" ? null : "got " + redirected);
  } catch (error) {
    report("webrequest-redirects", "threw " + error);
  }
  try {
    const header = await (await fetch("/net/headers")).text();
    report("webrequest-adds-request-header", header === "yes" ? null : "the server saw " + header);
  } catch (error) {
    report("webrequest-adds-request-header", "threw " + error);
  }
})();
