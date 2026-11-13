# Changelog

## 0.1.0 (November 13, 2026)

The first release, for Decidim 0.32 from 0.32.2 on.

- A link that ends in `?frontdoor=1`, to any page of a participatory process, an assembly, an initiative, a
  conference or a process group, opens that page without Decidim's navigation: a thin white band with a short
  trail of links, the page, and the legal links at the bottom.
- The visit stays that way through every space, Decidim's log-in pages, its verification pages and its Terms of
  Service page. Any other page shows Decidim's full navigation and ends the visit, as does `?frontdoor=0`.
- One cookie, `decidim_frontdoors`, which ends with the browser session and is listed in the "Essential" group of
  Decidim's cookie notice (English, Spanish, Catalan).
- Hooks into Decidim with one Deface edit: a line in `layouts/decidim/_head` that prints nothing. No migration,
  no setting, no admin screen, no script.

The rule is the one that has run on demo.gathers.today since November 12, 2026, from that application's own
code, with one addition (the verification pages) and new names (the switch was `?focus=1` there).
