// The walk: fifteen checks of the band and the trail, in headless Chromium at
// 390 and 1366 px, each in two browsers: a fresh one, and one that has
// already opened a page of the site, so that Decidim's service worker is in
// control of every page (it then fetches each page itself, as on a returning
// visitor's phone).
//
//   script/walk/run walk.cjs http://localhost:3033 tmp/walk [check numbers]
//
// It is written for the development application of this repository (README,
// "Tests"): a Decidim with its seed data, prepared by script/walk/prepare.rb.
// Pages are found by their links, because the seed data is random and
// component numbers in addresses change at every rebuild.
//
// The site must have Decidim's service worker on, as a production site does.
// A development server leaves it out unless DECIDIM_SERVICE_WORKER_ENABLED is
// true, which compose.yaml sets. The walk stops at once on a site without it.
//
// Writes <out>/walk.json (one record per step), <out>/walk.md (the same as
// tables, with what was expected of each step) and <out>/shots/ (the top
// 200 px of each step). It ends with exit code 1 when a step was not as
// expected or a check stopped.
//
// To run some checks again and keep the others' rows from an earlier run:
//   WALK_KEEP=tmp/walk/walk.json script/walk/run walk.cjs http://localhost:3033 tmp/walk 5 14
//
// A known limit of the module shows in the walk, and nothing here works
// around it. Decidim's service worker keeps a copy of every address for an
// hour and shows it when the server takes more than 3 seconds, and a
// development server sometimes does. The copy is the page as it was drawn
// then, with or without navigation. Every step tells such a copy from a page
// drawn now, by the token Decidim writes into each page it draws, and its
// verdict then names the step the copy was drawn at. (A copy of an answer the
// walk never saw in a page cannot be told this way.)
//
// It logs in as the organization's administrator and as a participant, the
// two accounts Decidim's seeds create. It presses a vote button, a sign
// button and a like button to see the log-in prompt; it casts no vote and
// signs nothing. Check 14 creates two accounts each time it runs and verifies
// one of them with the two example methods; check 15 writes the application's own head
// file (development_app/app/views/layouts/decidim/_head_extra.html.erb), runs
// checks 1 and 7 again and removes the file.
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const BASE = (process.argv[2] || "http://localhost:3033").replace(/\/$/, "");
const OUT = process.argv[3] || "tmp/walk";
const ONLY = process.argv.slice(4).map(Number);
const PW = process.env.WALK_PASSWORD || "decidim123456789";
const ADMIN = process.env.WALK_ADMIN || "admin@example.org";
const USER = process.env.WALK_USER || "user@example.org";
const COOKIE = "decidim_frontdoors";
const KEEP = process.env.WALK_KEEP;
const HEAD_EXTRA = "development_app/app/views/layouts/decidim/_head_extra.html.erb";
const BROWSERS = ["fresh", "worker in control"];
const SITE = {};
const rows = [];
// Decidim writes a new token into every page it draws. A page whose token
// this browser has already seen was not drawn now: Decidim's service worker
// showed the copy it keeps of each address for an hour, which it does when
// the server takes more than 3 seconds to answer.
const drawn = new WeakMap();
let BROWSER = null;
let LOOK = null;
fs.mkdirSync(path.join(OUT, "shots"), { recursive: true });

function snapshot() {
  const visible = (el) => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden";
  const text = (el) => (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim();
  const name = (el) => (el.textContent || "").replace(/\s+/g, " ").trim();
  const crumb = (el, shown) => {
    const r = el.getBoundingClientRect();
    return { shown, name: name(el), href: el.getAttribute("href"), width: Math.round(r.width), height: Math.round(r.height) };
  };
  const body = document.body.classList;
  const bar = document.querySelector("#menu-bar");
  const trail = document.querySelector(".menu-bar__breadcrumb-desktop");
  const one = document.querySelector(".menu-bar__breadcrumb-mobile");
  const crumbs = [];
  let shows = null;
  if (visible(trail)) {
    shows = "trail";
    trail.querySelectorAll(":scope > .menu-bar__breadcrumb-desktop__dropdown-trigger").forEach((el) => {
      if (!visible(el)) return;
      const dots = getComputedStyle(el, "::after").content.includes("…");
      crumbs.push(crumb(el, dots ? "…" : text(el)));
    });
  } else if (visible(one)) {
    shows = "one link";
    const el = one.querySelector(".menu-bar__breadcrumb-item");
    if (el) crumbs.push(crumb(el, "‹ " + text(el)));
  }
  const layout = document.querySelector(".layout-2col");
  const main = document.querySelector(".layout-2col__main");
  return {
    address: location.pathname + location.search,
    title: text(document.querySelector("#content h1") || document.querySelector("h1") || document.body).slice(0, 70),
    language: document.documentElement.lang,
    token: (document.querySelector('meta[name="csrf-token"]') || { content: null }).content,
    loaded: performance.timeOrigin,
    naked: body.contains("frontdoor"),
    start: body.contains("frontdoor-start"),
    back: body.contains("frontdoor-back"),
    band: bar && visible(bar) ? { height: Math.round(bar.getBoundingClientRect().height), background: getComputedStyle(bar).backgroundColor } : null,
    shows,
    crumbs,
    mainBar: visible(document.querySelector("#main-bar .main-bar")),
    decidimFocus: !!document.querySelector(".main-bar--focus-mode-back-button"),
    decidimBack: Array.from(document.querySelectorAll(".main-bar__back-button a")).filter(visible).map(text),
    adminBar: visible(document.querySelector("#admin-bar")) ? Array.from(document.querySelectorAll("#admin-bar a")).filter(visible).map(text) : null,
    follow: Array.from(document.querySelectorAll(".menu-bar__actions *, .menu-bar__actions-mobile *")).some(visible),
    footer: Array.from(document.querySelectorAll("footer a, footer button")).filter(visible).map(text),
    wide: document.documentElement.scrollWidth > window.innerWidth,
    worker: !!(navigator.serviceWorker && navigator.serviceWorker.controller),
    installersOwn: !!document.querySelector('meta[name="installers-own"]'),
    greyUnderWhite: layout && main ? Math.round(layout.getBoundingClientRect().bottom - main.getBoundingClientRect().bottom) : null,
    pageHeight: document.documentElement.scrollHeight,
  };
}

// Names in the seed data are long sentences, and Decidim cuts them short in
// places: two names are the same when their first twelve letters are.
const same = (shown, expected) => {
  if (expected === "*") return true;
  if (shown.startsWith("‹ ") !== expected.startsWith("‹ ")) return false;
  const a = shown.replace(/^‹ /, "").trim();
  const b = expected.replace(/^‹ /, "").trim();
  return a === b || (a.length >= 12 && a.slice(0, 12) === b.slice(0, 12));
};

// What was expected of a step, and what every page of a visit must measure.
//   naked: true | false     without navigation, or not
//   full: true              Decidim's full navigation
//   decidim: true           Decidim's own focus header (budget voting)
//   cookie: true | false    our cookie in the browser
//   start, back: true       the body classes
//   band: [...]             what the band shows; { wide: [...], narrow: [...] } when the widths differ
//   language: "es"          the page, its address and the band's links are in that language
//   own: true               the application's own head content is in the page
function judge(row, want) {
  const problems = [];
  if (row.naked) {
    if (!row.band || row.band.height !== 48) problems.push(`the band is ${row.band ? row.band.height : "not there"}, not 48 px`);
    const links = row.crumbs.filter((c) => c.href);
    if (links.some((c) => c.height < 44)) problems.push(`a link of the band is ${Math.min(...links.map((c) => c.height))} px tall, under 44`);
    if (row.mainBar) problems.push("the main bar is shown");
    if (row.follow) problems.push("the follow button is shown");
    if (row.footer.length !== 2) problems.push(`the footer holds ${row.footer.length} links, not the two legal ones`);
    if (row.wide) problems.push("the page is wider than the screen");
  }
  if (want.naked === true && !row.naked) problems.push("expected a page without navigation");
  if (want.naked === false && row.naked) problems.push("expected navigation");
  if (want.full && (row.naked || row.decidimFocus || !row.mainBar)) problems.push("expected Decidim's full navigation");
  if (want.decidim && (!row.decidimFocus || row.naked)) problems.push("expected Decidim's own focus header");
  if ("cookie" in want && row.cookie !== want.cookie) problems.push(want.cookie ? "our cookie is missing" : "our cookie is still there");
  if ("start" in want && row.start !== want.start[row.width < 1024 ? 1 : 0]) problems.push(`the page ${row.start ? "is" : "is not"} marked as the start of the trail`);
  if (want.back && !row.back) problems.push("expected the Back band");
  const band = Array.isArray(want.band) ? want.band : want.band && want.band[row.width < 1024 ? "narrow" : "wide"];
  if (band) {
    const shown = row.crumbs.map((c) => c.shown);
    if (shown.length !== band.length || !shown.every((words, i) => same(words, band[i]))) problems.push(`the band shows "${shown.join(" › ")}", expected "${band.join(" › ")}"`);
  }
  if (want.language) {
    if (row.language !== want.language) problems.push(`the page is in "${row.language}", not "${want.language}"`);
    if (!row.address.startsWith(`/${want.language}/`)) problems.push("the address lost its language");
    const astray = row.crumbs.filter((c) => c.href && !c.href.startsWith(`/${want.language}`));
    if (astray.length) problems.push(`a link of the band leaves the language: ${astray[0].href}`);
  }
  if (want.own && !row.installersOwn) problems.push("the application's own head content is missing");
  return problems;
}

async function rec(check, page, did, want = {}, extra = {}) {
  await page.waitForLoadState("networkidle").catch(() => {});
  const width = page.viewportSize().width;
  const row = { check, width, browser: BROWSER, at: new Date().toISOString(), step: rows.filter((r) => r.check === check && r.width === width && r.browser === BROWSER).length + 1, did, ...(await page.evaluate(snapshot)), ...extra };
  row.cookie = (await page.context().cookies()).some((c) => c.name === COOKIE);
  const tokens = drawn.get(page.context()) || drawn.set(page.context(), new Map()).get(page.context());
  const before = row.token && tokens.get(row.token);
  row.storedCopy = !!before && before.loaded !== row.loaded ? before.step : null; // the same token in another load of a page
  if (row.token && !before) tokens.set(row.token, { loaded: row.loaded, step: row.step });
  delete row.token;
  delete row.loaded;
  row.problems = judge(row, want);
  if (row.storedCopy) row.problems.unshift(`the service worker showed its stored copy of this address, the page as drawn at step ${row.storedCopy}, because the server took over 3 seconds (the module's known limit)`);
  row.shot = `shots/check-${String(check).padStart(2, "0")}-${width}-${BROWSER === BROWSERS[0] ? "fresh" : "worker"}-${String(row.step).padStart(2, "0")}.png`;
  await page.screenshot({ path: path.join(OUT, row.shot), clip: { x: 0, y: 0, width, height: 200 } });
  rows.push(row);
  const band = row.naked ? `${row.shows}: ${row.crumbs.map((c) => c.shown).join(" › ")}` : row.decidimFocus ? `Decidim's own focus header (${row.decidimBack.join(", ")})` : "full site";
  console.log(`check ${check} @${width} ${BROWSER} #${row.step} ${did}\n    ${row.address}\n    ${band}${row.cookie ? "" : "  [no cookie]"}${row.worker ? "  [worker]" : ""}${row.problems.length ? `\n    NOT AS EXPECTED: ${row.problems.join("; ")}` : ""}`);
  return row;
}

async function hideNotices(page) {
  await page.evaluate(() => {
    const notice = document.querySelector("#dc-dialog-wrapper");
    if (notice) notice.style.display = "none";
    // What a development machine adds to a page: decidim-dev's accessibility
    // badge and the profiler's.
    Array.from(document.querySelectorAll("body *")).forEach((el) => {
      if (getComputedStyle(el).position === "fixed" && /^\s*WAI WCAG/.test(el.textContent || "")) el.style.display = "none";
    });
    document.querySelectorAll(".profiler-results").forEach((el) => { el.style.display = "none"; });
  }).catch(() => {});
}

async function open(page, address) {
  await page.goto(BASE + address, { waitUntil: "domcontentloaded" });
  await hideNotices(page);
}

async function click(page, locator) {
  await Promise.all([page.waitForNavigation({ waitUntil: "domcontentloaded" }), locator.click()]);
  await hideNotices(page);
}

// The band's own links: "…", a crumb by its words, or whatever leads one step up.
async function pressDots(page) {
  const index = await page.evaluate(() => Array.from(document.querySelectorAll(".menu-bar__breadcrumb-desktop > a"))
    .findIndex((el) => el.getClientRects().length > 0 && getComputedStyle(el, "::after").content.includes("…")));
  if (index < 0) throw new Error(`no "…" in the band on ${page.url()}`);
  await click(page, page.locator(".menu-bar__breadcrumb-desktop > a").nth(index));
}
const pressCrumb = (page, words) => click(page, page.locator("#menu-bar a:visible", { hasText: words.slice(0, 12) }).first());
const pressUp = (page) => click(page, page.locator("#menu-bar a:visible").last());

const addresses = (page, inside) => page.evaluate((selector) => Array.from(document.querySelectorAll(`${selector} a[href]`)).map((a) => a.getAttribute("href").split("#")[0].split("?")[0]), inside);

// The first link in the page's content whose address matches; then anywhere
// in the page.
async function find(page, pattern, nth = 0) {
  for (const inside of ["#content", "body"]) {
    const found = [...new Set(await addresses(page, inside))].filter((h) => pattern.test(h));
    if (found[nth]) return found[nth];
  }
  throw new Error(`no link like ${pattern} on ${page.url()}`);
}

// The ideas among the links of this page's list. An amendment is left out:
// its page sits under the idea it amends, one crumb deeper (the crumb above
// it is an idea, in any language). The look at each one is taken in another
// browser, so that it is no page of this visit.
async function ideasOn(page, count) {
  const found = [];
  for (const idea of [...new Set(await addresses(page, "#content"))].filter((h) => /\/proposals\/\d+$/.test(h))) {
    const html = await (await LOOK.request.get(BASE + idea)).text();
    const above = Array.from(html.matchAll(/<a\b[^>]*menu-bar__breadcrumb-desktop__dropdown-trigger[^>]*>/g)).map((m) => (m[0].match(/href="([^"?#]+)/) || [])[1] || "");
    if (/\/proposals\/\d+$/.test(above[above.length - 1] || "")) continue;
    found.push(idea);
    if (found.length === count) break;
  }
  return found;
}

// Opens one idea from the list on this page.
async function openIdea(page, nth = 0) {
  const idea = (await ideasOn(page, nth + 1))[nth];
  if (!idea) throw new Error(`no idea to open on ${page.url()}`);
  await open(page, idea);
  return idea;
}

// The address of one idea of the process, looked up in the other browser.
async function anIdea() {
  await open(LOOK, SITE.proposals);
  const idea = (await ideasOn(LOOK, 1))[0];
  if (!idea) throw new Error("no idea in the process's list");
  return idea;
}

// The name of the page in Decidim's own breadcrumb: its last crumb.
const lastCrumb = (page) => page.evaluate(() => {
  const all = document.querySelectorAll(".menu-bar__breadcrumb-desktop > .menu-bar__breadcrumb-desktop__dropdown-trigger");
  return all.length ? (all[all.length - 1].textContent || "").replace(/\s+/g, " ").trim() : null;
});

// A browser that has already opened a page of the site: its service worker is
// installed and in control. The cookies are then cleared, so the check starts
// with no visit and no log-in, as in a fresh browser.
async function warmUp(page) {
  await open(page, "/en/");
  await page.evaluate(() => navigator.serviceWorker.ready);
  for (let i = 0; i < 5 && !(await page.evaluate(() => !!navigator.serviceWorker.controller)); i += 1) await open(page, "/en/");
  if (!(await page.evaluate(() => !!navigator.serviceWorker.controller))) throw new Error("the service worker never took control");
  await page.context().clearCookies();
}

async function login(page, email, form = "#content", password = PW) {
  await page.fill(`${form} input[name="user[email]"]`, email);
  await page.fill(`${form} input[name="user[password]"]`, password);
  await click(page, page.locator(`${form} form button[type="submit"]`).first());
}

// Presses a button that asks a logged-out visitor to log in, and waits for
// Decidim's prompt.
async function pressForPrompt(page, selector) {
  const button = page.locator(`${selector}:visible`).first();
  if (!(await button.count())) return null;
  const words = ((await button.innerText()) || (await button.getAttribute("aria-label")) || (await button.getAttribute("title")) || "").trim().replace(/\s+/g, " ");
  await button.click();
  await page.locator("#loginModal form").first().waitFor({ state: "visible", timeout: 10000 });
  return words;
}

// The newest email to this address that holds a link like the pattern, read
// from the development application's letter box, in another browser.
async function linkInEmail(to, pattern) {
  for (let i = 0; i < 30; i += 1) {
    const index = await (await LOOK.request.get(`${BASE}/letter_opener`)).text();
    const letters = [...new Set(Array.from(index.matchAll(/href="(\/letter_opener\/[^"/]+\/(?:rich|plain))"/g)).map((m) => m[1]))];
    for (const letter of letters) {
      const body = await (await LOOK.request.get(BASE + letter)).text();
      if (!body.includes(to)) continue;
      const link = body.replace(/&amp;/g, "&").match(pattern);
      if (link) return new URL(link[0]);
    }
    await new Promise((resolve) => { setTimeout(resolve, 1000); });
  }
  throw new Error(`no email to ${to} with a link like ${pattern}`);
}

const band = (wide, narrow) => ({ wide, narrow: narrow || wide });
const NAKED = { naked: true, cookie: true };
const FULL = { full: true, cookie: false };
const BACK = { naked: true, back: true, cookie: true, band: ["Back"] };

// Checks 1 and 7 are run twice: on their own, and as check 15 with the
// application's own head file in place.
const down_and_up = (check, more = {}) => async (page) => {
  const { space, spaceName: S, groupName: G, proposals, proposalsName: P } = SITE;
  await open(page, `${space}?frontdoor=1`);
  await rec(check, page, "land on the process's front page with ?frontdoor=1", { ...NAKED, start: [true, true], band: ["…", S], ...more });
  await open(page, proposals);
  await rec(check, page, `open ${P}`, { ...NAKED, start: [false, false], band: band(["…", S, P], [`‹ ${S}`]), ...more });
  await openIdea(page);
  await rec(check, page, "open one idea", { ...NAKED, band: band(["…", S, P, "*"], [`‹ ${P}`]), ...more });
  await pressCrumb(page, P);
  await rec(check, page, `press "${P}" in the band`, { ...NAKED, band: band(["…", S, P], [`‹ ${S}`]), ...more });
  await pressCrumb(page, S);
  await rec(check, page, "press the process's name in the band", { ...NAKED, band: ["…", S], ...more });
  await pressDots(page);
  await rec(check, page, 'press "…"', { ...NAKED, band: ["…", G], ...more });
  await pressDots(page);
  await rec(check, page, 'press "…" again', { ...FULL, ...more });
  await open(page, space);
  await rec(check, page, "open the process again, no parameter", { ...FULL, ...more });
};

const kept_pages = (check, more = {}) => async (page) => {
  const { space, spaceName: S } = SITE;
  const back = { ...BACK, ...more };
  await open(page, `${space}?frontdoor=1`);
  await rec(check, page, "land on the process with ?frontdoor=1", { ...NAKED, band: ["…", S], ...more });
  await click(page, page.locator('footer a[href*="/pages/terms-of-service"]:visible').first());
  await rec(check, page, "press Terms of Service in the footer", back);
  await pressUp(page);
  await rec(check, page, 'press "Back"', { ...NAKED, band: ["…", S], ...more });
  await open(page, "/en/users/sign_up");
  await rec(check, page, "the sign-up page", back);
  const terms = await page.evaluate(() => (document.querySelector('#content a[href*="/pages/terms-of-service"]') || { getAttribute: () => null }).getAttribute("href"));
  if (terms) {
    await open(page, terms);
    await rec(check, page, "open the sign-up form's link to the terms", back);
  }
  for (const [name, address] of [["forgotten password", "/en/users/password/new"], ["email confirmation", "/en/users/confirmation/new"], ["account unlock", "/en/users/unlock/new"]]) {
    await open(page, address);
    await rec(check, page, `the ${name} page`, back);
  }
  await open(page, space);
  await rec(check, page, "open the process again, no parameter", { ...NAKED, band: ["…", S], ...more });
  await open(page, "/en/users/sign_in");
  await rec(check, page, "the log-in page", back);
  await login(page, USER);
  await rec(check, page, "log in as the participant on the log-in page", { ...NAKED, band: ["…", S], ...more });
};

const CHECKS = {
  // 1. Down from a space's front page and back up, then up and out.
  1: down_and_up(1),
  // 2. Land on one meeting, then on one idea. From 1024 px up the trail starts
  //    at the space; under it, at the page landed on.
  2: async (page) => {
    const { spaceName: S, proposalsName: P, meetingsName: M } = SITE;
    const wide = page.viewportSize().width >= 1024;
    await open(LOOK, SITE.meetings);
    const meeting = await find(LOOK, /\/meetings\/\d+$/);
    const idea = await anIdea();

    await open(page, `${meeting}?frontdoor=1`);
    await rec(2, page, "land on one meeting with ?frontdoor=1", { ...NAKED, start: [true, true], band: band(["…", S, M, "*"], ["…", "*"]) });
    await pressUp(page);
    await rec(2, page, wide ? "press the last link of the trail (its list)" : 'press "…" (one step up)', { ...NAKED, band: band(["…", S, M], ["…", M]) });
    await open(page, `${idea}?frontdoor=1`);
    await rec(2, page, "land on one idea with ?frontdoor=1", { ...NAKED, start: [true, true], band: band(["…", S, P, "*"], ["…", "*"]) });
    await pressUp(page);
    await rec(2, page, wide ? `press "${P}" in the band` : 'press "…" (one step up)', { ...NAKED, band: band(["…", S, P], ["…", P]) });
    await openIdea(page, 1);
    await rec(2, page, "open a second idea from the list", { ...NAKED, band: band(["…", S, P, "*"], [`‹ ${P}`]) });
    await pressUp(page);
    await rec(2, page, "press the link one step up", { ...NAKED, band: band(["…", S, P], ["…", P]) });
    await pressDots(page);
    await rec(2, page, wide ? 'press "…" (one step above the space)' : 'press "…" (one step up)', { ...NAKED, band: band(["…", SITE.groupName], ["…", S]) });
  },
  // 3. An assembly under another, then the process it links to.
  3: async (page) => {
    const { assembly, assemblyName: A, parentName: PA, space, spaceName: S } = SITE;
    await open(page, `${assembly}?frontdoor=1`);
    await rec(3, page, "land on an assembly that has a parent, with ?frontdoor=1", { ...NAKED, band: ["…", A] });
    const related = page.locator(`#content a[href*="${space.replace(/^\/en/, "")}"]:visible`).first();
    const pressed = (await related.count()) > 0;
    if (pressed) await click(page, related);
    else await open(page, space);
    await rec(3, page, pressed ? "press its related process" : "open a process by its address, no parameter", { ...NAKED, band: ["…", S] });
    await open(page, await find(page, /\/f\/\d+\/[a-z_]+$/));
    await rec(3, page, "open one of its parts", { ...NAKED, band: band(["…", S, "*"], [`‹ ${S}`]) });
    await open(page, assembly);
    await rec(3, page, "open the assembly again, no parameter", { ...NAKED, band: ["…", A] });
    await pressDots(page);
    await rec(3, page, 'press "…": its parent assembly', { ...NAKED, band: ["…", PA] });
    await pressDots(page);
    await rec(3, page, 'press "…" again: the list of assemblies', FULL);
  },
  // 4. The same assembly as the organization's administrator.
  4: async (page) => {
    if (page.viewportSize().width < 1000) return;
    await open(page, "/en/users/sign_in");
    await login(page, ADMIN);
    await open(page, `${SITE.assembly}?frontdoor=1`);
    const row = await rec(4, page, "as the administrator: land on the assembly with ?frontdoor=1", { ...NAKED, band: ["…", SITE.assemblyName] });
    if (!row.adminBar) row.problems.push("Decidim's admin strip is not shown");
    await open(page, await find(page, /\/f\/\d+\/meetings$/));
    await rec(4, page, "as the administrator: open its meetings", NAKED);
    await open(page, await find(page, /\/meetings\/\d+$/));
    await rec(4, page, "as the administrator: open one meeting", NAKED);
  },
  // 5. An address without /en, into budget voting and back, logging in there.
  5: async (page) => {
    await open(page, `${SITE.space.replace(/^\/en/, "")}?frontdoor=1`);
    await rec(5, page, "land on the process by an address without /en, with ?frontdoor=1", { ...NAKED, band: ["…", SITE.spaceName] });
    await open(page, SITE.budgets);
    let row = await rec(5, page, "open its budgets", { cookie: true });
    if (!/\/projects/.test(row.address)) {
      await open(page, await find(page, /\/budgets\/\d+(\/projects)?$/));
      row = await rec(5, page, "open the budget", { cookie: true });
    }
    const words = await pressForPrompt(page, '#content [data-dialog-open="loginModal"]');
    await login(page, USER, "#loginModal");
    row = await rec(5, page, `press "${words}", log in as the participant in the prompt`, { decidim: true, cookie: true });
    await click(page, page.locator(".main-bar__back-button a:visible").first());
    row = await rec(5, page, "press voting's own back link", { cookie: true });
    if (row.decidimFocus) {
      await click(page, page.locator(".main-bar__back-button a:visible").first());
      row = await rec(5, page, "press voting's own back link again", { cookie: true });
    }
    if (!row.naked) row.problems.push("on the way out of voting the page should be without navigation again");
  },
  // 6. An initiative (log in at the sign button, sign nothing) and a conference.
  6: async (page) => {
    const { initiative, conference, conferenceName: C } = SITE;
    await open(page, `${initiative}?frontdoor=1`);
    await rec(6, page, "land on one initiative with ?frontdoor=1", { ...NAKED, band: ["…", "*"] });
    const words = await pressForPrompt(page, '#content [data-dialog-open="loginModal"]');
    if (words) {
      await login(page, USER, "#loginModal");
      await rec(6, page, `press "${words}", log in as the participant in the prompt (nothing signed)`, { ...NAKED, band: ["…", "*"] });
    } else {
      await rec(6, page, "no button with a log-in prompt on this initiative", NAKED);
    }
    await pressDots(page);
    await rec(6, page, 'press "…": the list of initiatives', { full: true, cookie: false });
    await page.context().clearCookies();
    await open(page, `${conference}?frontdoor=1`);
    await rec(6, page, "land on the conference with ?frontdoor=1", { ...NAKED, band: ["…", C] });
    await open(page, await find(page, /\/conferences\/[^/]+\/program\/\d+/));
    await rec(6, page, "open its program", { ...NAKED, band: band(["…", C, "*"], [`‹ ${C}`]) });
    await open(page, `${conference}/speakers`);
    await rec(6, page, "open its speakers", NAKED);
    await pressUp(page);
    await rec(6, page, "press the link one step up", NAKED);
  },
  // 7. The pages outside every space that stay without navigation during a
  //    visit: the terms of service and the log-in family. The band is one
  //    link, "Back".
  7: kept_pages(7),
  // 8. Two tabs.
  8: async (page) => {
    const { space, spaceName: S, assembly, assemblyName: A, initiative, proposalsName: P } = SITE;
    const other = await page.context().newPage();
    await open(page, `${space}?frontdoor=1`);
    await rec(8, page, "tab 1: land on the process with ?frontdoor=1", { ...NAKED, band: ["…", S] });
    await open(other, `${assembly}?frontdoor=1`);
    await rec(8, other, "tab 2: land on the assembly with ?frontdoor=1", { ...NAKED, band: ["…", A] });
    await open(page, SITE.proposals);
    await rec(8, page, `tab 1: open ${P}`, { ...NAKED, band: band(["…", S, P], [`‹ ${S}`]) });
    await open(other, initiative);
    await rec(8, other, "tab 2: open an initiative, no parameter", { ...NAKED, band: ["…", "*"] });
    await openIdea(page);
    await rec(8, page, "tab 1: open one idea", { ...NAKED, band: band(["…", S, P, "*"], [`‹ ${P}`]) });
    await open(other, assembly);
    await rec(8, other, "tab 2: back to the assembly, no parameter", { ...NAKED, band: ["…", A] });
    await pressUp(page);
    await rec(8, page, "tab 1: press the link one step up", { ...NAKED, band: band(["…", S, P], [`‹ ${S}`]) });
    await other.close();
  },
  // 9. The grey block under a short page.
  9: async (page) => {
    if (page.viewportSize().width < 1000) return;
    const measure = async (did, want) => {
      const off = await page.evaluate(() => {
        const style = document.createElement("style");
        style.textContent = "body.frontdoor .layout-2col{grid-auto-rows:max-content}";
        document.head.appendChild(style);
        const gap = Math.round(document.querySelector(".layout-2col").getBoundingClientRect().bottom - document.querySelector(".layout-2col__main").getBoundingClientRect().bottom);
        style.remove();
        return gap;
      });
      const row = await rec(9, page, did, want, { greyUnderWhiteWithoutOurRule: off });
      if (row.naked && row.greyUnderWhite !== 0) row.problems.push(`the white column ends ${row.greyUnderWhite} px above the bottom of the content area`);
      await page.screenshot({ path: path.join(OUT, row.shot.replace(".png", "-whole.png")), fullPage: true });
    };
    await open(page, `${SITE.space}?frontdoor=1`);
    await open(page, SITE.posts);
    await measure(`a short page: ${SITE.postsName} in the process`, NAKED);
    await open(page, SITE.proposals);
    await measure(`a long page: ${SITE.proposalsName} in the process`, NAKED);
    await open(page, `${SITE.posts}?frontdoor=0`);
    await measure("the short page with the full site", FULL);
  },
  // 10. Where ?frontdoor=1 does nothing, and what nobody else sees.
  10: async (page) => {
    for (const address of ["/en/?frontdoor=1", "/en/processes?frontdoor=1", "/en/users/sign_in?frontdoor=1", "/en/pages/terms-of-service?frontdoor=1", "/en/", SITE.space, "/en/users/sign_in", "/en/pages/terms-of-service", `${SITE.space}?focus=1`]) {
      await page.context().clearCookies();
      await open(page, address);
      await rec(10, page, `no visit on: open ${address}`, FULL);
    }
  },
  // 11. Keyboard only, then the pointer: what is painted, and how tall the
  //     link is that can be pressed.
  11: async (page) => {
    const width = page.viewportSize().width;
    const look = () => {
      const el = document.activeElement && document.activeElement !== document.body ? document.activeElement : document.querySelector("#menu-bar a:hover");
      const style = getComputedStyle(el);
      const block = getComputedStyle(el, "::before");
      const r = el.getBoundingClientRect();
      const inBand = !!el.closest("#menu-bar");
      return {
        words: (el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60),
        where: inBand ? "band" : el.closest("#content") ? "content" : el.closest("header") ? "header" : el.closest("footer") ? "footer" : "page",
        size: `${Math.round(r.width)} x ${Math.round(r.height)}`,
        height: Math.round(r.height),
        text: style.color,
        block: inBand ? { color: block.backgroundColor, height: Math.round(parseFloat(block.height)), corners: block.borderRadius } : null,
        painted: inBand ? `${block.backgroundColor}, ${Math.round(parseFloat(block.width))} x ${Math.round(parseFloat(block.height))} px, corners ${block.borderRadius}` : "",
        ring: style.boxShadow !== "none" ? `box-shadow ${style.boxShadow}` : `outline ${style.outlineWidth} ${style.outlineStyle} ${style.outlineColor}`,
      };
    };
    // Under the pointer and under the keyboard a link of the band is 44 px
    // tall, its words white on a block of the site's color, 28 px tall with
    // 4 px corners.
    const measured = (row, stops, how) => {
      const inBand = stops.filter((s) => s.where === "band");
      if (!inBand.length) row.problems.push(`${how}: no link of the band was reached`);
      inBand.forEach((s) => {
        if (s.height !== 44) row.problems.push(`${how}: "${s.words}" is ${s.height} px tall, not 44`);
        if (s.block.height !== 28 || s.block.corners !== "4px") row.problems.push(`${how}: the block behind "${s.words}" is ${s.block.height} px tall with ${s.block.corners} corners, not 28 and 4px`);
        if (s.text !== "rgb(255, 255, 255)" || /rgba\(0, 0, 0, 0\)|transparent/.test(s.block.color)) row.problems.push(`${how}: "${s.words}" is not white on a painted block (${s.text} on ${s.block.color})`);
      });
    };
    const crop = (name) => page.screenshot({ path: path.join(OUT, `shots/check-11-${width}-${BROWSER === BROWSERS[0] ? "fresh" : "worker"}-${name}.png`), clip: { x: 0, y: 0, width, height: 200 } });
    await open(page, `${SITE.space}?frontdoor=1`);
    await open(page, SITE.proposals);
    await openIdea(page);
    const stops = [];
    for (let i = 0; i < 12; i += 1) {
      await page.keyboard.press("Tab");
      const stop = await page.evaluate(look);
      stops.push(stop);
      if (stop.where === "band") await crop(`tab-${i + 1}`);
      if (stop.where === "content") break;
    }
    let row = await rec(11, page, "an idea reached from the process: Tab from the top of the page", NAKED, { tabStops: stops });
    measured(row, stops, "keyboard");
    await page.evaluate(() => document.activeElement.blur());
    const hovers = [];
    const links = page.locator("#menu-bar a:visible");
    for (let i = 0; i < await links.count(); i += 1) {
      await links.nth(i).hover();
      hovers.push(await page.evaluate(look));
      await crop(`hover-${i + 1}`);
    }
    await page.mouse.move(0, 400);
    row = await rec(11, page, "the same page: the pointer over each link of the band", NAKED, { hovers });
    measured(row, hovers, "pointer");
  },
  // 12. Once navigation is back, it is back; and a page fetched in the
  //     background ends nothing.
  12: async (page) => {
    const { space, spaceName: S } = SITE;
    for (const [name, address] of [["search", "/en/search"], ["a profile", SITE.profile], ["another help page", SITE.helpPage]]) {
      await page.context().clearCookies();
      await open(page, `${space}?frontdoor=1`);
      await rec(12, page, "land on the process with ?frontdoor=1", { ...NAKED, band: ["…", S] });
      await open(page, address);
      await rec(12, page, `open ${name}`, FULL);
      await open(page, space);
      await rec(12, page, "go back into the process, no parameter", FULL);
    }
    await page.context().clearCookies();
    await open(page, `${space}?frontdoor=1`);
    await rec(12, page, "land on the process with ?frontdoor=1", { ...NAKED, band: ["…", S] });
    await open(page, "/en/account");
    await rec(12, page, "open the account page, which sends a logged-out visitor to the log-in page", BACK);
    await open(page, space);
    await rec(12, page, "go back into the process, no parameter", { ...NAKED, band: ["…", S] });
    const status = await page.evaluate(() => fetch("/offline").then((response) => response.status));
    await open(page, space);
    await rec(12, page, `the page fetches Decidim's offline page in the background (answer ${status}), then the process is opened again`, { ...NAKED, band: ["…", S] });
  },
  // 13. A visit begun on a Spanish address stays in Spanish, and "Back" is
  //     Decidim's Spanish word.
  13: async (page) => {
    const es = (address) => address.replace(/^\/en\//, "/es/");
    const spanish = { ...NAKED, language: "es" };
    await open(page, `${es(SITE.space)}?frontdoor=1`);
    await rec(13, page, "land on the process by its Spanish address, with ?frontdoor=1", { ...spanish, band: ["…", "*"] });
    await open(page, await find(page, /^\/es\/.*\/f\/\d+\/proposals$/));
    await rec(13, page, "open its proposals by the page's own link", spanish);
    await openIdea(page);
    await rec(13, page, "open one idea", spanish);
    await pressUp(page);
    await rec(13, page, "press the link one step up", spanish);
    await click(page, page.locator('footer a[href*="/pages/terms-of-service"]:visible').first());
    await rec(13, page, "press the terms of service in the footer", { ...spanish, back: true, band: ["Atrás"] });
    await open(page, "/es/users/sign_in");
    await rec(13, page, "the log-in page, in Spanish", { ...spanish, back: true, band: ["Atrás"] });
    await pressUp(page);
    await rec(13, page, 'press "Atrás": back where the visit started', { ...spanish, band: ["…", "*"] });
    await pressDots(page);
    await rec(13, page, 'press "…": the process group, in Spanish', { ...spanish, band: ["…", "*"] });
  },
  // 14. Creating an account ends the visit: Decidim sends a new account to
  //     the home page. The sign-up page and the terms are without navigation;
  //     after the form the home page shows full navigation and the visit is
  //     over; the link in the confirmation email then opens with full
  //     navigation too. Run twice: from a button that needs an account only,
  //     and from one that also needs a verification. Then the other case: an
  //     account that already exists logs in during a visit and stays without
  //     navigation through the verification pages, back to the idea.
  14: async (page) => {
    const width = page.viewportSize().width;
    const P = SITE.proposalsName;
    const onIdea = { ...NAKED, band: band(["…", SITE.spaceName, P, "*"], ["…", "*"]) };
    const verification = /\/authorizations(\/|\?|$)|\/(id_documents|postal_letter|csv_census|sms)(\/|$)/;
    const idea = await anIdea();
    const account = (kind) => {
      const who = `walk-${Date.now().toString(36)}-${width}${BROWSER === BROWSERS[0] ? "f" : "w"}${kind}`;
      return { name: `Walk ${who.replace(/[^a-z0-9]/g, " ")}`, email: `${who}@example.org`, password: `Fd-${Math.random().toString(36).slice(2, 12)}-Zq7!` };
    };

    // A new account. button: what the visitor presses on the idea to be asked
    // to log in. pending: whether that button also needs a verification.
    const signUp = async (button, pending, kind) => {
      const one = account(kind);
      const with_ = pending ? "which needs an account and two verifications" : "which needs an account only";
      await page.context().clearCookies();
      await open(page, `${idea}?frontdoor=1`);
      await rec(14, page, `new account, ${pending ? "a verification pending" : "nothing to verify"}: land on one idea with ?frontdoor=1`, onIdea);
      const words = await pressForPrompt(page, button);
      await click(page, page.locator('#loginModal a[href*="/users/sign_up"]:visible').first());
      await rec(14, page, `press "${words}", ${with_}, then "Create an account" in the prompt: the sign-up page`, BACK);
      await open(page, await page.evaluate(() => document.querySelector('#content a[href*="/pages/terms-of-service"]').getAttribute("href")));
      await rec(14, page, "open the sign-up form's link to the terms", BACK);
      await open(page, "/en/users/sign_up");
      await rec(14, page, "the sign-up page again", BACK);
      await page.fill('#content input[name="user[name]"]', one.name);
      await page.fill('#content input[name="user[email]"]', one.email);
      await page.fill('#content input[name="user[password]"]', one.password);
      await page.check("#registration_user_tos_agreement");
      await page.check("#registration_user_newsletter"); // unticked, the form asks about it in a prompt of its own
      await page.waitForTimeout(5000); // Decidim's spam trap refuses a form sent within a few seconds
      await click(page, page.locator('#content form button[type="submit"]').first());
      const sent = await rec(14, page, "fill in the form and send it: Decidim sends the new account to the home page, which ends the visit", FULL);
      if (!/^\/en\/?$/.test(sent.address)) sent.problems.push("expected Decidim to send the new account to the home page");
      await open(page, idea);
      await rec(14, page, "find the idea again, no parameter: the visit is over", FULL);
      const confirm = await linkInEmail(one.email, /https?:\/\/[^"'\s<]+confirmation_token=[\w-]+/);
      await open(page, confirm.pathname + confirm.search);
      const landed = await rec(14, page, `press the link in the confirmation email: Decidim logs the account in and sends it ${pending ? 'to its "verify your account" page' : "to the home page"}, with full navigation`, FULL);
      const there = pending ? /\/authorizations\/onboarding_pending/ : /^\/en\/?$/;
      if (!there.test(landed.address)) landed.problems.push(`after the confirmation link Decidim was expected at ${pending ? "the verify-your-account page" : "the home page"}`);
      return one;
    };

    await signUp("#content [data-proposal-vote-button]", false, "a");
    const one = await signUp("#content #like-button", true, "b");

    // The account now exists and has two verifications to do. A browser with
    // no log-in and no visit: it arrives by the link, presses Like and logs in
    // in the prompt.
    await page.context().clearCookies();
    await open(page, `${idea}?frontdoor=1`);
    await rec(14, page, "existing account, not logged in: land on the idea with ?frontdoor=1", onIdea);
    const words = await pressForPrompt(page, "#content #like-button");
    await login(page, one.email, "#loginModal", one.password);
    const sentTo = await rec(14, page, `press "${words}", log in in the prompt: Decidim sends the account to its "verify your account" page`, BACK);
    if (!/\/authorizations\/onboarding_pending/.test(sentTo.address)) sentTo.problems.push("expected the verify-your-account page");
    for (let i = 0; i < 8 && verification.test(new URL(page.url()).pathname); i += 1) {
      const form = page.locator('#content form:has(input[name^="authorization_handler["])').first();
      if (await form.count()) {
        const field = (name) => form.locator(`input[name="authorization_handler[${name}]"]`);
        if (await field("document_number").count()) await field("document_number").fill(`${Date.now().toString().slice(-7)}${width}X`);
        if (await field("passport_number").count()) await field("passport_number").fill(`A${Date.now().toString().slice(-7)}${width}`);
        const method = new URL(page.url()).searchParams.get("handler");
        await click(page, form.locator('button[type="submit"]').first());
        const done = !verification.test(new URL(page.url()).pathname);
        await rec(14, page, `fill in the form of the method "${method}" and send it${done ? ": Decidim returns to the idea" : ""}`, done ? onIdea : BACK);
      } else {
        const next = page.locator('#content a[href*="authorizations/new?handler="]:visible').first();
        if (!(await next.count())) break;
        await click(page, next);
        await rec(14, page, "press the first method that is still to do", BACK);
      }
    }
    const last = rows[rows.length - 1];
    if (!last.address.startsWith(idea)) last.problems.push("after the last verification Decidim should have returned to the idea");
    await open(page, "/en/authorizations");
    await rec(14, page, "open the list of the participant's verifications", BACK);
    const own = page.locator('#content a[href*="/id_documents"], #content a[href*="/postal_letter"], #content a[href*="/csv_census"]').first();
    if (await own.count()) {
      await click(page, own);
      await rec(14, page, "press a method that has pages of its own", BACK);
    }
    await pressUp(page);
    await rec(14, page, 'press "Back": the idea the visit started at', onIdea);
  },
  // 15. Checks 1 and 7 again, with the application holding a head file of its
  //     own (other content in it): the one line in Decidim's head still runs,
  //     and the application's content is still printed.
  15: async (page) => {
    await down_and_up(15, { own: true })(page);
    await page.context().clearCookies();
    await kept_pages(15, { own: true })(page);
  },
};

function table() {
  const bad = rows.filter((r) => r.problems && r.problems.length);
  const lines = ["# Frontdoors: the walk of the band and the trail", "", `Site: ${BASE}. Each row is one step of \`script/walk/walk.cjs\`; the recording is \`walk.json\`.`,
    "\"Band\" is what the top of the page showed: a trail (\"… › Proposals\"), one link up (\"‹ Proposals\"), Decidim's own", "focus header, or the full site. A crumb in [brackets] was a link. Heights and widths are in px.",
    "Each check runs in two browsers: \"fresh\" (its first page is the first page of the site it opens) and \"worker in", "control\" (it has opened the home page first, so Decidim's service worker fetches every page). \"Worker\" says whether",
    "the service worker controlled that page. \"As expected\" is the script's own verdict on the step: what the rule says the",
    "page should show, and on every page of a visit a band 48 px tall, no link of it under 44 px, no main bar, no follow", "button, a footer of two links and no page wider than the screen.", "",
    `${rows.length} steps; ${bad.length} not as expected, of which ${rows.filter((r) => r.storedCopy).length} showed the service worker's stored copy of a page.`, ""];
  lines.push("| Check | Steps | Not as expected | Of those, the worker's stored copy | Run (UTC) |", "| --- | --- | --- | --- | --- |");
  for (const check of [...new Set(rows.map((r) => r.check))]) {
    const of = rows.filter((r) => r.check === check);
    const times = of.map((r) => r.at).filter(Boolean).sort();
    const when = times.length ? `${times[0].slice(0, 16).replace("T", " ")} to ${times[times.length - 1].slice(11, 16)}` : "";
    lines.push(`| ${check} | ${of.length} | ${of.filter((r) => r.problems.length).length} | ${of.filter((r) => r.storedCopy).length} | ${when} |`);
  }
  lines.push("");
  for (const check of [...new Set(rows.map((r) => r.check))]) {
    lines.push(`## Check ${check}`, "", "| Browser | Width | Step | What was done | Address | Band | Band height; smallest link | Our cookie | Worker | As expected | Notes |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const r of rows.filter((row) => row.check === check)) {
      const shown = r.naked ? r.crumbs.map((c) => (c.href ? `[${c.shown}]` : c.shown)).join(" › ") : r.decidimFocus ? `Decidim's focus header: ${r.decidimBack.join(", ")}` : "full site";
      const small = r.naked && r.crumbs.some((c) => c.href) ? Math.min(...r.crumbs.filter((c) => c.href).map((c) => c.height)) : "";
      const notes = [];
      if (r.note) notes.push(r.note);
      if (r.storedCopy) notes.push(`the service worker's stored copy, from step ${r.storedCopy}`);
      if (r.naked && r.crumbs[0] && r.crumbs[0].shown === "…") notes.push(`"…" is ${r.crumbs[0].name} (${r.crumbs[0].href})`);
      if (r.naked && r.back && r.crumbs[0]) notes.push(`leads to ${r.crumbs[0].href}`);
      if (r.naked) notes.push(`footer: ${r.footer.join(", ")}`);
      if (r.adminBar) notes.push(`admin bar: ${r.adminBar.join(", ")}`);
      if (r.language && r.language !== "en") notes.push(`page language: ${r.language}`);
      if (r.installersOwn) notes.push("the application's own head content is in the page");
      if (r.greyUnderWhiteWithoutOurRule !== undefined) notes.push(`white column ends ${r.greyUnderWhite} px above the bottom of the content area (${r.greyUnderWhiteWithoutOurRule} px without our rule)`);
      if (r.tabStops) notes.push(r.tabStops.map((s, i) => `Tab ${i + 1}: ${s.where}, "${s.words}", link ${s.size}${s.painted ? `, text ${s.text}, painted ${s.painted}` : ""}`).join("<br>"));
      if (r.hovers) notes.push(r.hovers.map((s, i) => `Pointer on link ${i + 1}: "${s.words}", link ${s.size}, text ${s.text}, painted ${s.painted}`).join("<br>"));
      const verdict = r.problems.length ? `**NO**: ${r.problems.join("; ")}` : "yes";
      lines.push(`| ${r.browser} | ${r.width} | ${r.step} | ${r.did} | \`${r.address}\` | ${shown} | ${r.band && r.naked ? `${r.band.height}; ${small}` : ""} | ${r.cookie ? "yes" : "no"} | ${r.worker ? "yes" : "no"} | ${verdict} | ${notes.join("; ")} |`);
    }
    lines.push("");
  }
  return lines.join("\n").replace(/\|\|/g, "| |");
}

// The pages of the seed data the checks use, found by their links in a
// browser of its own, before any visit starts.
async function lookUp() {
  await open(LOOK, "/en/");
  const registered = await LOOK.evaluate(() => new Promise((resolve) => {
    if (!navigator.serviceWorker) { resolve(false); return; }
    navigator.serviceWorker.ready.then(() => resolve(true));
    setTimeout(() => resolve(false), 15000);
  }));
  if (!registered) {
    console.log(`STOP: ${BASE} has no service worker. A production site has one; a development server leaves it out unless DECIDIM_SERVICE_WORKER_ENABLED=true (compose.yaml sets it: docker compose --profile development_app up -d web).`);
    process.exit(1);
  }
  await open(LOOK, "/en/processes");
  const listed = [...new Set(await addresses(LOOK, "#content"))];
  const candidates = listed.filter((h) => /\/processes\/[^/]+$/.test(h));
  for (const group of listed.filter((h) => /\/processes_groups\/\d+$/.test(h))) {
    await open(LOOK, group);
    candidates.push(...(await addresses(LOOK, "#content")).filter((h) => /\/processes\/[^/]+$/.test(h)));
  }
  for (const candidate of [...new Set(candidates)]) {
    await open(LOOK, candidate);
    const above = await LOOK.evaluate(() => Array.from(document.querySelectorAll(".menu-bar__breadcrumb-desktop > a")).map((a) => [a.getAttribute("href"), (a.textContent || "").replace(/\s+/g, " ").trim()]));
    const group = above.find(([href]) => /\/processes_groups\/\d+$/.test(href || ""));
    if (!group) continue;
    Object.assign(SITE, { space: candidate, spaceName: await lastCrumb(LOOK), groupName: group[1] });
    break;
  }
  if (!SITE.space) throw new Error("no process in a process group in the seed data");
  for (const part of ["proposals", "meetings", "budgets", "posts"]) SITE[part] = await find(LOOK, new RegExp(`/f/\\d+/${part}$`));
  for (const part of ["proposals", "meetings", "posts"]) {
    await open(LOOK, SITE[part]);
    SITE[`${part}Name`] = await lastCrumb(LOOK);
  }
  await open(LOOK, SITE.proposals);
  for (const idea of [...new Set(await addresses(LOOK, "#content"))].filter((h) => /\/proposals\/\d+$/.test(h))) {
    await open(LOOK, idea);
    SITE.profile = (await addresses(LOOK, "#content")).find((h) => /\/profiles\/[^/]+$/.test(h));
    if (SITE.profile) break;
  }
  if (!SITE.profile) throw new Error("no idea with a link to its author's profile in the seed data");
  // An assembly that sits under another: Decidim's breadcrumb names its parent.
  await open(LOOK, "/en/assemblies");
  const assemblies = [...new Set(await addresses(LOOK, "#content"))].filter((h) => /\/assemblies\/[^/]+$/.test(h));
  for (const assembly of assemblies) {
    await open(LOOK, assembly);
    const above = await LOOK.evaluate(() => Array.from(document.querySelectorAll(".menu-bar__breadcrumb-desktop > a")).map((a) => [a.getAttribute("href"), (a.textContent || "").replace(/\s+/g, " ").trim()]));
    const parent = above.find(([href]) => /\/assemblies\/[^/]+$/.test(href || "") && href !== assembly);
    if (!parent) continue;
    Object.assign(SITE, { assembly, assemblyName: await lastCrumb(LOOK), parentName: parent[1] });
    break;
  }
  if (!SITE.assembly) throw new Error("no assembly with a parent in the seed data");
  await open(LOOK, "/en/initiatives");
  const initiatives = [...new Set(await addresses(LOOK, "#content"))].filter((h) => /\/initiatives\/i-\d+$/.test(h));
  for (const initiative of initiatives) {
    await open(LOOK, initiative);
    SITE.initiative = SITE.initiative || initiative;
    if (await LOOK.locator('#content [data-dialog-open="loginModal"]:visible').count()) { SITE.initiative = initiative; break; }
  }
  await open(LOOK, "/en/conferences");
  SITE.conference = await find(LOOK, /\/conferences\/[^/]+$/);
  await open(LOOK, SITE.conference);
  SITE.conferenceName = await lastCrumb(LOOK);
  await open(LOOK, "/en/pages");
  SITE.helpPage = [...new Set(await addresses(LOOK, "#content"))].find((h) => /\/pages\/[^/]+$/.test(h) && !/terms-of-service/.test(h));
  console.log(`The pages of this walk:\n${Object.entries(SITE).map(([key, value]) => `    ${key}: ${value}`).join("\n")}`);
}

(async () => {
  const browser = await chromium.launch();
  LOOK = await (await browser.newContext({ viewport: { width: 1366, height: 768 } })).newPage();
  await lookUp();
  for (const check of Object.keys(CHECKS).map(Number)) {
    if (ONLY.length && !ONLY.includes(check)) continue;
    if (check === 15) {
      if (!fs.existsSync("development_app") || !/\/\/(localhost|127\.0\.0\.1)[:/]/.test(`${BASE}/`)) {
        console.log("check 15 skipped: it writes the development application's own head file, and this is not the development application");
        continue;
      }
      fs.mkdirSync(path.dirname(HEAD_EXTRA), { recursive: true });
      fs.writeFileSync(HEAD_EXTRA, '<%# Written by script/walk/walk.cjs for check 15, and removed by it. Nothing of Frontdoors is in this file. %>\n<meta name="installers-own" content="head-extra-is-here">\n');
      await new Promise((resolve) => { setTimeout(resolve, 1500); });
    }
    try {
      for (const kind of BROWSERS) {
        for (const width of [390, 1366]) {
          BROWSER = kind;
          const context = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 768 }, isMobile: width < 500, hasTouch: width < 500 });
          const page = await context.newPage();
          try {
            if (kind !== BROWSERS[0]) await warmUp(page);
            await CHECKS[check](page);
          } catch (error) {
            const why = error.message.split("\n")[0];
            console.log(`check ${check} @${width} ${kind} STOPPED: ${why}`);
            rows.push({ check, width, browser: kind, step: 99, did: `STOPPED: ${why}`, address: page.url().replace(BASE, ""), naked: false, crumbs: [], footer: [], decidimBack: [], problems: [`stopped: ${why}`] });
          }
          await context.close();
        }
      }
    } finally {
      if (check === 15) fs.rmSync(HEAD_EXTRA, { force: true });
    }
  }
  await browser.close();
  if (KEEP) {
    const run = new Set(rows.map((r) => r.check));
    rows.push(...JSON.parse(fs.readFileSync(KEEP, "utf8")).filter((r) => !run.has(r.check)));
    rows.sort((a, b) => a.check - b.check);
  }
  fs.writeFileSync(path.join(OUT, "walk.json"), JSON.stringify(rows, null, 1));
  fs.writeFileSync(path.join(OUT, "walk.md"), table());
  const bad = rows.filter((r) => r.problems.length);
  console.log(`${rows.length} steps, ${bad.length} not as expected -> ${path.join(OUT, "walk.md")}`);
  process.exit(bad.length ? 1 : 0);
})();
