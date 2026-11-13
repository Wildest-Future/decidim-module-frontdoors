// Pictures of the band for the README: crops that show text only, at 390 and
// 1366 px wide.
//
//   script/walk/run shots.cjs <outdir> <kind>:<label>=<address>[,<address>...] ...
//
// kind "band":  the band alone: Decidim's breadcrumb bar on a page of a visit,
//               or Decidim's own header on a page outside one. Writes
//               <day>-band-<label>-<width>.png.
// kind "hover": the same crop with the pointer on a link of the band (the
//               second one, a written crumb, when there are several). Writes
//               <day>-band-hover-<label>-<width>.png.
// kind "head":  everything above the page's own content: Decidim's main bar
//               and breadcrumb bar on a page outside a visit, the band on a
//               page of one. Writes <day>-head-<label>-<width>.png.
// Several addresses separated by commas are opened one after the other in the
// same browser (the visit is remembered in a cookie); the picture is of the
// last one. The cookie notice is hidden first.
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

const OUT = process.argv[2];
const TARGETS = process.argv.slice(3).map((arg) => {
  const [, kind, label, addresses] = arg.match(/^(band|hover|head):([^=]+)=(.*)$/) || [];
  if (!kind) throw new Error(`not <kind>:<label>=<address>: ${arg}`);
  return { kind, label, addresses: addresses.split(",") };
});
const DAY = process.env.SHOTS_DAY || new Date().toISOString().slice(0, 10);
fs.mkdirSync(OUT, { recursive: true });

function look() {
  const notice = document.querySelector("#dc-dialog-wrapper");
  if (notice) notice.style.display = "none";
  // What a development machine adds to a page: decidim-dev's accessibility
  // badge and the profiler's.
  Array.from(document.querySelectorAll("body *")).forEach((el) => {
    if (getComputedStyle(el).position === "fixed" && /^\s*WAI WCAG/.test(el.textContent || "")) el.style.display = "none";
  });
  document.querySelectorAll(".profiler-results").forEach((el) => { el.style.display = "none"; });
  const visible = (el) => !!el && el.getClientRects().length > 0;
  const box = (el) => {
    if (!visible(el)) return null;
    const r = el.getBoundingClientRect();
    return { top: Math.round(r.top + window.scrollY), bottom: Math.round(r.bottom + window.scrollY) };
  };
  const text = (el) => (el.innerText || "").replace(/\s+/g, " ").trim();
  const trail = document.querySelector(".menu-bar__breadcrumb-desktop");
  const one = document.querySelector(".menu-bar__breadcrumb-mobile .menu-bar__breadcrumb-item");
  let words = [];
  if (visible(trail)) {
    words = Array.from(trail.querySelectorAll(":scope > .menu-bar__breadcrumb-desktop__dropdown-trigger")).filter(visible)
      .map((el) => (getComputedStyle(el, "::after").content.includes("…") ? "…" : text(el)));
  } else if (visible(one)) {
    words = [`‹ ${text(one)}`];
  }
  return {
    bar: box(document.querySelector("#menu-bar")),
    mainBar: box(document.querySelector("#main-bar")),
    words,
    frontdoor: document.body.classList.contains("frontdoor"),
  };
}

(async () => {
  const browser = await chromium.launch();
  for (const { kind, label, addresses } of TARGETS) {
    for (const width of [390, 1366]) {
      const context = await browser.newContext({ viewport: { width, height: 1400 }, isMobile: width < 500, hasTouch: width < 500 });
      const page = await context.newPage();
      let response = null;
      for (const address of addresses) response = await page.goto(address, { waitUntil: "networkidle" });
      const info = await page.evaluate(look);
      const band = info.bar || info.mainBar;
      if (kind === "hover") {
        const links = page.locator("#menu-bar a:visible");
        await links.nth((await links.count()) > 1 ? 1 : 0).hover();
      }
      const top = kind === "head" ? 0 : band.top;
      const file = path.join(OUT, `${DAY}-${{ band: "band", hover: "band-hover", head: "head" }[kind]}-${label}-${width}.png`);
      await page.screenshot({ path: file, clip: { x: 0, y: top, width, height: band.bottom - top } });
      const shows = info.frontdoor ? `a page of a visit, band "${info.words.join(" › ")}"` : "full site";
      console.log(`${kind} ${label}-${width}: ${response.status()} ${addresses[addresses.length - 1]} -> ${width} x ${band.bottom - top} px, ${fs.statSync(file).size} bytes, ${shows}`);
      await context.close();
    }
  }
  await browser.close();
})();
