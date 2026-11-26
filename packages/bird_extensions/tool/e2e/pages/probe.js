// What an ad blocker is to do.
eventually("ad-script-by-path-blocked", () => (window.loaded_pagead_js_adsbygoogle_js ? "it ran" : null), 3000);
eventually("ad-server-blocked", () => (window.externalAd === "refused" ? null : "it was " + window.externalAd));
eventually("ad-slot-hidden", () =>
  getComputedStyle(document.getElementById("slot")).display === "none" ? null : "it is still shown");
// What a dark theme is to do.
eventually("page-darkened", () => {
  const [r, g, b] = getComputedStyle(document.body).backgroundColor.match(/\d+/g).map(Number);
  return r + g + b < 250 ? null : "the background is " + getComputedStyle(document.body).backgroundColor;
});
