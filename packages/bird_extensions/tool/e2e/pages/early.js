// The first script of the page. What a document_start content script does has to
// be visible to it.
window.earlySeenByPage = document.documentElement.getAttribute("data-c-early");
window.pageVariable = "from page";
window.frames_ = {};
window.blankFrameRan = false;
addEventListener("message", (event) => {
  if (event.data && event.data.conformanceBlank) window.blankFrameRan = true;
  if (event.data && event.data.conformanceFrame) window.frames_[event.data.conformanceFrame] = event.data.hasRoot;
});
document.addEventListener("from-content", (event) => (window.eventFromContent = event.detail));
