// Runs in blank frames of the pages the tests browse.
if (location.href === "about:blank") window.parent.postMessage({ conformanceBlank: true }, "*");
