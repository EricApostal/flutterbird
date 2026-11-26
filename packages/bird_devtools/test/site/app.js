function go() {
  const data = { a: 1, b: "two", c: [1, 2, 3], d: null, e: undefined, f: true, g: new Map([[1, 2]]), big: 10n };
  console.log("clicked", data, document.body);
  console.warn("a warning %s", "here");
  return data;
}
console.log("loaded", 42);
console.info("info msg");
console.error("error msg");
console.debug("debug msg");
console.table([{ x: 1, y: 2 }]);
console.group("grp");
console.log("inside");
console.groupEnd();
console.trace("trace label");
localStorage.setItem("lk", "lv");
sessionStorage.setItem("sk", "sv");
document.cookie = "ck=cv; path=/";
fetch("style.css").then(r => r.text()).then(t => console.log("fetched", t.length));
setTimeout(() => { throw new TypeError("boom async"); }, 100);
