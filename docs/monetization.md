# Tether Rally: monetization specification

Nov 14, 2026 · Guillaume (English translation of the French spec, with the decisions taken since in the review thread)

Tether Rally goes free-to-play on Google Play: rewarded ads the player chooses to watch, a "No ads" purchase, the existing paint packs, and a few widely spaced full-screen ads. This document says what to build, where it plugs into the current code and in what order. All numbers are defaults to tune (last section), not settled decisions.

> **Reconfirm the app id first.** The current id `io.github.guillaumefont.tetherracing` is temporary and will change. Before any Play upload, any Play product, AdMob app or ad unit is created, ask Guillaume to reconfirm the final app id: it can never change after the first upload.

All in-game text is English (the game has no translation system yet); the strings quoted below are the ones to show. The original French spec is kept in [monetization/spec-fr.md](monetization/spec-fr.md).

## Status (Nov 15, 2026)

Everything game-side is built and merged, running behind stubs (a test build grants purchases at once and plays a 1 s fake ad; a store build has neither stubs nor self-update):

- PR #100: `Store`, `Ads` and `Monetization` services with stubs.
- PR #101: "x2 coins" on the results, Gold ghost (51 traces at the Gold time, offered after a run without Gold), Daily Detour with 3 attempts (first lap free, practice, +1 attempt for an ad), full-screen ads, No ads / Restore / Privacy in Settings, the "Android Play" (AAB) export preset.
- PR #102: starter pack and coin packs (shop under the Garage), Daily Detour streak with "Save my streak", ideal line.

Before/after screenshots: [results](monetization/results_coins-before-after.jpg), [results phase 3](monetization/results_coins-phase3-before-after.jpg), [Daily Detour](monetization/menu_daily-before-after.jpg), [settings](monetization/settings-before-after.jpg), [home](monetization/menu_home-before-after.jpg), [Garage](monetization/menu_garage-phase3-before-after.jpg).

**Waiting on Guillaume** (step 6 of phase 1 and the soft launch need his accounts):

1. The final app id (reconfirm before anything below).
2. An upload keystore, stored as a GitHub secret.
3. Play Console account and products: `remove_ads`, `chrome_pack`, `neon_pack`, `starter_pack`, `coins_s`, `coins_m`.
4. AdMob account, app and one ad unit per placement, plus the UMP consent message.
5. A website for `app-ads.txt` and the privacy policy; Data safety and target audience forms.

Then: real Billing, AdMob and UMP plugins with the Gradle template in CI, a test on a real phone, the closed test (12 testers, 14 days), and the Play Games daily leaderboard.

## Goal and principles

- **A new attempt at a skill challenge is never paid for.** Medal attempts in Time trial stay unlimited, with no ad and no energy. We charge for extras, shortcuts and cosmetics.
- **Nothing touches race times.** Coins and purchases only buy looks (rule already written in `wallet.gd` and `cosmetics.gd`), so records and rankings stay fair.
- **Ads are a choice.** Every rewarded ad is a button the player taps. Forced ads are rare, never during a race, never in the first session.
- **"No ads" also gives the rewards without watching.** A payer is never worse off than a watcher.
- **Accepted trade-off (2026-11-14):** since Gold is required to advance in the Road Trip, the Gold ghost for an ad helps progression. That is accepted: the player still has to drive the Gold lap.
- **Everything goes through two services** (`Store` and a new `Ads`), each with a stub in debug and preview builds, so the menus never know Play Billing or AdMob directly.

## What already exists in the code

The economy is already there; what is missing is real billing, ads and the Daily Detour limits.

| Piece | File | Current state | What changes |
| --- | --- | --- | --- |
| Purchases | `scripts/store.gd` | Stub: `chrome_pack` and `neon_pack` at €1.99, bought at once in debug/preview, "Soon" in release, ownership in `user://store.cfg` | Google Play Billing backend, new products, restore |
| Coins | `scripts/wallet.gd` | Earned per medal (`FIRST`/`REPEAT`), Daily Detour and awards; spent in the Garage | Ad multipliers, coin packs later |
| Cosmetics | `scripts/cosmetics.gd`, `scripts/garage.gd` | Paints, liveries, ropes; `unlock` by coins or `product`; buy button in the Garage | New products wired to the same `unlock.product` |
| Daily Detour | `scripts/daily.gd`, "DAILY DETOUR" banner in `menu.gd` | One track + variant a day, unlimited attempts, `BASE` 40 + 30 per tier, an improvement pays the difference | Limited scored attempts, free practice, streak |
| Results screen | `main.gd` `_show_results()` and `_pay()`, `ui.gd` `show_results()` | Shows coins earned as badges | "x2 coins" button, Gold ghost offer, full-screen ad trigger |
| Ghosts | `scripts/records.gd`, `main.gd` `_ghost_sample()` | Only the player's best lap, in Time trial | New "Gold medal" ghost |
| Medal times | `scripts/medals.gd`, `scripts/medal_times.gd`, `tools/gen_medals.gd` | Tiers Bronze, Silver, Gold, Pivot = AI reference time x 1.30 / 1.15 / 1.03 / 0.96 | Source of the Gold ghost traces and the ideal line |
| Android export | `export_presets.cfg` | `gradle_build/use_gradle_build=false`; CI builds release-template APKs with the `preview,self_update` features | Gradle build required for the Billing and AdMob plugins (already blocking for the AAB); a separate store preset |

Not there yet: an ad service, an online leaderboard (records are local), a session counter and a Shop screen. Settings > "Reset progress" already keeps paid packs; it must keep "No ads" too.

## Architecture

Two static services, modelled on `store.gd`, and one settings file. The menus only call these interfaces.

| File | Role | Interface |
| --- | --- | --- |
| `scripts/store.gd` (extended) | Purchases. Play Billing backend on Android, current stub in debug/preview | `available()`, `buy(id, callback)`, `owns(id)`, `restore()`, `price(id)` (localised price read from Play), change notification |
| `scripts/ads.gd` (new) | Ads. AdMob backend on Android, stub in debug/preview that grants the reward after 1 s | `rewarded_ready(placement)`, `show_rewarded(placement, on_reward)`, `maybe_interstitial(trigger)`, `ads_removed()` |
| `scripts/monetization.gd` (new) | Every tunable constant (last section) and the daily counters | constants + `used_today(key)`, `use(key)` |

**Backends.** Google Play Billing through the official Godot plugin (`godot-sdk-integrations/godot-google-play-billing`) and AdMob through a maintained Godot 4 plugin, chosen after checking compatibility with the project's Godot version (4.7.2). Both need `gradle_build/use_gradle_build=true`.

**Common rules.**

- `buy()` and `show_rewarded()` become asynchronous: the caller gets a callback, the UI shows a "working" state and never blocks the race.
- A non-consumable purchase is acknowledged as soon as it is granted, or Play refunds it after 3 days. At launch, `restore()` reads the purchases back from Play, which becomes the source of truth; `user://store.cfg` is only a cache.
- An ad reward is granted only on AdMob's "reward earned" callback, never just because the ad closed. No ad ready: the button is greyed with "No video right now", never an error.
- If `Store.owns("remove_ads")`, `Ads` shows nothing and `show_rewarded()` grants the reward at once; the button loses its video icon.
- The stub stays the behaviour of debug and preview builds (the `preview` feature `store.gd` already uses), so everything can be tested without a Play account. **The store build is a separate export preset (AAB, Gradle) that never has `preview` (the stub would hand out purchases for free) nor `self_update` (AGENTS.md rule); a test checks it.**

## Rewarded ads

Three placements, all extras on top of a race, never a way to buy a race back. None appears in the tutorial or in Off the Map (which pays nothing).

### 1. Double the coins (`double_coins`)

- **Where:** results screen, `main.gd` `_show_results()`. `_pay()` already knows the medal + Daily Detour total; it returns it as well as the text line.
- **When:** only if that total is above 0. Award coins (collected in the Passport) are not doubled.
- **Effect:** an "x2 coins" button under the badges. After the ad, `Wallet.add(total)` a second time, the badge becomes "+N x2 COINS" and the button goes. Once per results screen.
- **Limit:** `DOUBLE_COINS_PER_DAY` (10 by default), to keep the cosmetics economy readable.

### 2. Gold medal ghost (`gold_ghost`)

- **Where (decided by Guillaume, 2026-11-14):** only on the results screen (next to Again), after a failed attempt: a Time trial run finished without Gold, on a track + variant where the player doesn't have Gold yet. No button before the start (the Road Trip has no pre-race page since PR #96).
- **Effect:** unlocks for good, on that track + variant, a second ghost that laps exactly at the Gold time. It drives alongside the player's ghost, in another colour, under the existing ghost option.
- **New content (decided 2026-11-14: only where it is useful):** one trace per track for the Standard, Reverse and Obstacles variants (17 x 3). No Collect trace: there the medal is the score of the whole run, not a lap. Generated by a tool next to `tools/gen_medals.gd`: it drives the AI, records its lap the way `race.gd` already records a Time trial lap (30 samples a second), then rescales time to finish at the Gold time. Files in `res://ghosts/gold/`, in the binary format of `records.gd`, regenerated when a layout changes (like `medal_times.gd`).
- **Storage:** unlocks in `wallet.cfg`, section `ghosts`. They are cleared by "Reset progress".

### 3. Ideal line (`ideal_line`)

- **Where:** the results screen (and the Special Stages / Daily Detour event pages, the only pre-race pages left).
- **Effect:** for the next run only, the path of the Gold trace is drawn on the ground as a discreet ribbon, with a mark where the AI hooks and lets go. Nothing changes in the physics.
- **New content:** reuses the Gold ghost traces; the hook and release instants must be added to the recording. Rendering in `world_view.gd`.

**For all of them:** with "No ads", all three are free (the Gold ghost is then unlocked everywhere, the ideal line becomes a Settings option).

## Daily Detour

We limit the reward, not the game: 3 scored attempts a day (Guillaume, 2026-11-14), the best counts, then free practice with no reward.

**Scored attempts**

- Only a run started from the "DAILY DETOUR" banner counts. Today `main.gd` calls `Daily.claim()` for any Time trial run on today's track + variant (Special Stages and Road Trip stops included). The banner already starts an event of kind `"daily"`; `main.gd` must keep that kind and claim only for it. The same track raced from Special Stages or the Road Trip stays a normal run (medals and medal coins).
- An attempt is used when the countdown ends. Quitting or restarting during the first lap gives it back (decided by Guillaume, 2026-11-14: one crash in the first bend shouldn't cost an attempt); from the second lap on, quitting or restarting uses it, otherwise it could be replayed endlessly.
- Payment doesn't change: `BASE` + `PER_TIER` per tier on the first finished attempt, then the difference if a later attempt does better. That is already "the best counts".
- New in `daily.gd`: `attempts_left()`, `use_attempt()`, `best_today()` (the best time, which is not stored today: only the tier is), kept in the `daily` section of `wallet.cfg` with the day (reset when the date changes, like `paid_tier()`).
- The banner shows the attempts left ("2 attempts") and today's best time.

**Free practice**

- At 0 attempts, the banner starts the same track in practice mode: normal timer and ghost, no coins and no daily best, like Off the Map. The track record and its medals stay possible, since any Time trial can earn them.

**Bonus attempt for an ad (`daily_extra`)**

- At 0 attempts, the banner and the results screen offer "+1 scored attempt" for an ad, at most `DAILY_EXTRA_PER_DAY` times (1 by default).

**Streak (phase 3)**

- A day counts in the streak as soon as a scored attempt is finished. Coin bonus on days 3 and 7, then every 7 days (`STREAK_BONUS`).
- One missed day can be caught up: at the next launch, a card offers "Save my streak" for an ad (`streak_save`), at most once per 7 days. Otherwise the streak goes back to 1.
- The day is the device's (`Daily.today()`), with no server. Changing the phone's clock lets a player cheat on attempts, which is acceptable as long as nothing is ranked online.

**Leaderboard:** there is none today (local records). A daily leaderboard goes through Play Games Services, which the production audit already recommends; after the soft launch, with a server-side clock check.

## Purchases

Three products at launch and coin packs later, all declared in `Store.PRODUCTS` and created with the same id in the Play Console. Displayed prices come from Play (local currency); the table's prices are proposals.

| Id | Play type | Proposed price | Content | Phase |
| --- | --- | --- | --- | --- |
| `remove_ads` | non-consumable | €3.49 | No more full-screen ads, ad rewards without watching | 1 |
| `chrome_pack` | non-consumable | €1.99 | Existing: Chrome, Rose gold, Black chrome | 1 |
| `neon_pack` | non-consumable | €1.99 | Existing: three neon paints, Neon trim livery, neon rope | 1 |
| `starter_pack` | non-consumable | €4.99 | `remove_ads` + `neon_pack` + 1000 coins | 3 |
| `coins_s`, `coins_m` | consumable | €0.99 / €2.99 | 1500 / 5000 coins | 3, if the data justifies it |

**No ads**

- Sold in three places: a line in Settings, a small card in the Garage, and a "No ads?" link under every rewarded-ad button.
- `Ads.ads_removed()` reads `Store.owns("remove_ads") or Store.owns("starter_pack")`.

**Paint packs**

- Nothing to change in `cosmetics.gd`: `unlock.product` already points at the right id. `garage.gd` (lines 196 to 225) moves to the asynchronous purchase and shows Play's price instead of the fixed "€1.99" text.
- `cosmetics.gd` must accept an item unlocked by several products (`neon_pack` or `starter_pack`).

**Starter pack**

- Offered once, as a card after the results screen of the 5th finished race (`STARTER_AFTER_RACES`), never over a medal or award animation. It then stays visible in the Garage.
- Hidden if the player already owns `remove_ads` or `neon_pack` (decided 2026-11-14: one starter product only, no `starter_pack_b`).

**Coin packs**

- Only if coins buy things players want: at the soft launch, first look at how many players empty their wallet in the Garage. Consumables: `consume` after `Wallet.add()`.

**Restore:** a "Restore purchases" button in Settings calls `Store.restore()`. "Reset progress" touches no purchase.

## Full-screen ads (interstitials)

At most one full-screen ad every 4 finished races and at least `INTERSTITIAL_MIN_GAP_S` (7 min) apart, never in the first session, never during a race. Races last 30 to 60 s, so the race count alone would mean an ad every 3 to 4 minutes (agreed 2026-11-14).

- **Trigger:** `Ads.maybe_interstitial("after_results")`, called when the player leaves the results screen (Again, Next or Menu). Never when the results appear, nor over a medal, world-unlock or award animation (`_world_moment()`, `_award_moment()`).
- **Counter:** races finished since the last full-screen ad, in `wallet.cfg`. One shows when it reaches `INTERSTITIAL_EVERY` (4) and the last full-screen ad was at least `INTERSTITIAL_MIN_GAP_S` ago (wall-clock time, kept across launches), then it goes back to 0.
- **First session:** an app launch counter (new, in `settings.cfg`). No full-screen ad while it is 1, nor before `INTERSTITIAL_MIN_RACES` (6) races in total.
- **No doubling up:** no full-screen ad within `INTERSTITIAL_COOLDOWN_S` (120 s) of a rewarded ad or another full-screen ad.
- **Excluded:** tutorial, Off the Map, Daily Detour practice, 2-player races on one phone (Two for the Road).
- **Pause:** the game is already on its results, so nothing to pause; the music (`music.gd`) ducks during the ad and comes back after.

## Measurement, Play compliance and consent

Ads change the Play listing: GDPR consent, the Data safety form and a privacy policy must be done before the first closed test with ads.

**Consent**

- Google UMP form (shipped with AdMob) at first launch in Europe, before the first ad request. A "Privacy choices" link in Settings reopens it.
- Without consent, AdMob serves non-personalised ads; the game works the same.

**Play listing** (completes points 10, 11 and 14 of `docs/production-readiness.md`)

- Data safety: declare the advertising ID and the data AdMob collects, and purchases through Google Play.
- Permission `com.google.android.gms.permission.AD_ID` in the Android export.
- Target audience: declare 13 and over, otherwise the game falls under the Families rules (certified ads only, more constraints). The content rating can stay PEGI 3.
- "Contains ads" and "In-app purchases" labels.
- `app-ads.txt`: AdMob needs it at the root of the developer website listed on Play; plan that website (agreed 2026-11-14).
- Families risk: a cartoon look can make Play treat the game as appealing to children even when declared 13+, which would force Families-certified ads. Check the listing and art against the policy before the closed test.

**Store build and app id (agreed 2026-11-14)**

- A separate store export preset (AAB, Gradle, signed with the upload key) without `preview` and `self_update`; a CI test fails if the store preset carries either feature.
- The app id will change (Guillaume, 2026-11-14): the current `io.github.guillaumefont.tetherracing` is temporary. It can't change after the first Play upload and the products are tied to it, so no Play upload and no Play product is created until Guillaume gives the final id. Changing it also means test APKs no longer update the installed app (new app id = new app).
- Real purchases can't be tested on the self-updating test APKs: billing needs a build installed from a Play test track (internal testing) with the same app id and signing.

**Platforms without ads** (web, later iOS and Steam until they have their own ad or store backends): rewarded features are free there or hidden, never stuck. The web test build gets the `preview` feature so the stubs can be tried in the browser.

**Measurement at the soft launch**

- Phase 1 without an analytics SDK: the Play Console gives retention and purchase revenue, AdMob gives ad views per active user and per placement (one ad unit per placement).
- Numbers to watch: D1 and D7 retention, rewarded ads watched per active player per day, share of players buying "No ads", revenue per active player per day.
- An analytics SDK (Firebase) only if those numbers aren't enough to decide; it would change the Data safety form again.

## Build order and acceptance criteria

Three phases, each delivered as small PRs with their tests (AGENTS.md rule: every new test file gets its step in `.github/workflows/sim.yml`).

1. **Phase 1: what brings 80% (before the soft launch)**
   1. `ads.gd`, `monetization.gd`, asynchronous `store.gd`, with their stubs. Test `tests/monetization_test.gd`: the stub grants, `remove_ads` stops full-screen ads and grants without an ad.
   2. "x2 coins" ad on the results. Test: the wallet gets the total twice, once per screen, the daily limit holds, nothing in the tutorial or Off the Map.
   3. Gold traces generated for the 17 tracks x 3 variants (no Collect) and an unlockable Gold ghost, offered on the results after a run without Gold. Test: every trace finishes its lap at the Gold time within 0.05 s.
   4. Daily Detour: 3 scored attempts, practice, bonus attempt. Tests in `tests/economy_test.gd`: a 4th attempt pays nothing, quitting during the first lap uses no attempt, quitting later uses one, Special Stages on the same track uses nothing, reset on the next day.
   5. Light full-screen ads. Test: none at first launch nor before 6 races, then one every 4, never after the tutorial.
   6. Real backends: Gradle build, Billing plugin, AdMob plugin, UMP, products created in the Play Console, test on a real phone with AdMob test units and a licence-tester account.
2. **Phase 2: soft launch** in one or two small countries, after the mandatory closed test (12 testers, 14 days). Criterion to move on: D1 retention and rewarded ads per player per day, read over two weeks.
3. **Phase 3: depending on the numbers:** starter pack, streak and "Save my streak", ideal line, new cosmetics, coin packs if the Garage empties, daily leaderboard via Play Games.

The ideal line is in phase 3 because it needs new rendering in `world_view.gd`; it can move up to phase 1 if the Gold ghost is done early, since it reuses its traces.

## Tunable parameters

All these values live in `scripts/monetization.gd` and are proposals to revisit after the soft launch.

| Constant | Default | Effect |
| --- | --- | --- |
| `DOUBLE_COINS_PER_DAY` | 10 | "x2 coins" per day |
| `DAILY_ATTEMPTS` | 3 | Daily Detour scored attempts |
| `DAILY_EXTRA_PER_DAY` | 1 | Bonus attempts for an ad (2 at most) |
| `STREAK_BONUS` | day 3: 50, day 7: 150, then +150 every 7 days | Streak coins |
| `STREAK_SAVE_EVERY_DAYS` | 7 | One streak save per period |
| `INTERSTITIAL_EVERY` | 4 | Finished races between two full-screen ads (3 to 4) |
| `INTERSTITIAL_MIN_RACES` | 6 | Races before the first full-screen ad |
| `INTERSTITIAL_COOLDOWN_S` | 120 | Seconds with no full-screen ad after a rewarded ad |
| `INTERSTITIAL_MIN_GAP_S` | 420 | Minimum time between two full-screen ads (6 to 8 min) |
| `STARTER_AFTER_RACES` | 5 | Race after which the starter pack is offered |
| `remove_ads` price | €3.49 | Between €2.99 and €3.99 |
| `starter_pack` price | €4.99 | Cheaper than its parts bought separately (€5.48 + coins) |

**Open questions**

- Is an unlocked Gold ghost unlocked for good (proposed here) or for one day, which would show more ads?
- "No ads" gives "x2 coins" for free: to watch, since a buyer then earns twice as fast as the others.
- The final app id (it will change; not given yet).
