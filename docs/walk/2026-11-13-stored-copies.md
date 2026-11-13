# The service worker's stored copy in the walk of November 13, 2026

From `script/walk/stored_copies.rb`, over [the walk](2026-11-13-walk.md) (12:33 to 1:04 pm Boston, the development
application on a laptop) and the development application's log. Decidim's service worker keeps a copy of every
address for an hour and shows it when the server takes more than 3 seconds to answer. The walk tells such a copy
from a page drawn now by the token Decidim writes into every page it draws; a copy of an answer the walk never
saw in a page cannot be told this way. Nothing in the walk avoids the copy.

Steps: 512. Steps that showed the service worker's stored copy: 2.

| Check | Browser | Width | Step | Address | The copy was drawn at step | Shown | Our cookie | The server answered this step's request in |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 14 | fresh | 390 | 20 | `/en/processes/marine-nursery/f/7/proposals/1` | 13 | full navigation | yes | 3311 ms |
| 14 | worker in control | 390 | 23 | `/en/processes/marine-nursery/f/7/proposals/1` | 20 | no navigation | yes | 3186 ms |

`/en/processes/marine-nursery/f/7/proposals/1`: 34 requests during the walk, the server's times in ms: 2242, 2260, 2263, 2272, 2273, 2289, 2301, 2307, 2311, 2312, 2317, 2319, 2331, 2335, 2351, 2352, 2370, 2376, 2384, 2393, 2400, 2405, 2413, 2536, 2546, 2599, 2759, 2774, 2788, 2872, 2915, 2945, 3186, 3311

All page requests the server completed during the walk: 2787; over 3,000 ms: 10; median 414 ms, slowest 3327 ms.

Both steps are in check 14, at 390 px. In the first, the visit was on and the idea came back from the copy drawn
minutes earlier outside a visit: full navigation inside a visit. In the second the copy was the page as drawn
during the visit, so it showed what the server would have shown.

An earlier run of check 14 alone, the same day at 12:20 to 12:28 pm, before the walk could tell a copy: the
first of these two steps showed full navigation in all four of its browsers, when the server answered in 3,640,
3,865, 3,285 and 3,282 ms; the same address took 2,546 to 2,917 ms on the requests that showed the fresh page.
