// Runs at document_start in an isolated world. It proves, from the page's side,
// that: the script ran, `browser` exists, storage works, and the page cannot
// see what the extension defined.
(async () => {
  const { visits = 0 } = await browser.storage.local.get('visits');
  await browser.storage.local.set({ visits: visits + 1 });

  window.addEventListener('DOMContentLoaded', () => {
    const banner = document.createElement('div');
    banner.id = 'flutterbird-hello';
    banner.textContent = browser.i18n.getMessage('banner', String(visits + 1));
    document.body.appendChild(banner);
  });

  // Not visible to the page: this is the extension's own world.
  globalThis.extensionSecret = 'only the extension sees this';
})();
