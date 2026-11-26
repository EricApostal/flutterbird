// The strict page's policy still binds the page's own scripts.
const refused = (what) => {
  try {
    what();
    return "it was allowed";
  } catch (_) {
    return null;
  }
};
// NB: These wait, so that they are made after content scripts have run.
setTimeout(() => {
  report("page-eval-still-blocked", refused(() => eval("1 + 1")));
  report("page-trusted-types-still-enforced", refused(() => {
    document.createElement("div").innerHTML = "<b>x</b>";
  }));
}, 1500);
