# StandPoint (CommitPath) — prototype

A phone-first recruiting and training app for high school baseball players.
A player enters their profile once, logs numbers over time, and the app shows:

- **StandPoint:** which college level their numbers fit today (Top D1, mid-major D1, D2, D3, JUCO) and the exact gaps to the next level.
- **Train:** a weekly lift and speed schedule, an info button on every exercise, weight logged on every exercise, maxes, strength per pound of body weight, bar speed, jump and sprint tests, and pounds moved.
- **Recruit:** NCAA contact dates by class, a yearly checklist, and email, DM and coach-note templates filled in from the profile.
- **Schools:** about 1,550 baseball programs (every NCAA D1, D2 and D3 program, every NAIA program and about 390 junior colleges nationwide, plus Texas and Oklahoma at every level with coaches), filtered to the range the player picks at sign-up. Each school has a fit badge, senior timing, coaches, a 10-step contact tracker and messages addressed to the chosen coach.
- **Post:** builds an X caption from the player's numbers. The player always taps Post themselves.
- **More** (demos on one device): plans and payments (individual plan, club license, coaching add-on; Stripe Payment Links slot), club admin (roster, coaches, club lift plan, roster progress), coach inbox for video reviews with assigned drills, and install-to-home-screen. Two features are built but switched off in `FEATURES`: college-coach search (`collegeSearch`, after there's a large base of players) and softball (`softball`, once we know its recruiting process; the app is baseball only for now).

Live prototype (owner only until shared): https://claude.ai/artifact/TRD6j1Vq7Enetjz7Tsk6qT

## What this is, and what it isn't yet

This is a **single-file front-end prototype** (`index.html`, plain HTML, CSS and JavaScript, no framework, no build step). It is good for demos and user testing. It is **not** production software yet:

- **No backend, accounts or sync.** Everything saves in the browser's localStorage on one device. Clearing the browser deletes it.
- **No security review.** The code was written quickly with AI help and has not been audited. Stress-test it before real users rely on it.
- **Data is hand-collected.** Coach names and emails exist for Texas only, copied from team staff pages on Nov 3, 2026. Staffs change every year.

## Files

| Path | What it is |
|---|---|
| `index.html` | The entire app. Open it in any browser. |
| `data/ncaa*.txt` | NCAA baseball programs by state: `ST|name|division|conference|athletics site`, from the NCAA member directory (Nov 3, 2026). |
| `data/naia.txt`, `data/juco.txt` | NAIA and junior-college baseball programs: `State|name|NAIA or JUCO|conference||city`, from public college lists (Nov 4, 2026). Junior colleges are incomplete in some states (names P to Z after Maryland). Confirm against official NAIA and NJCAA sources. |
| `data/softball/*.txt` | NCAA softball programs, Texas and Oklahoma (NCAA member directory, Nov 4, 2026). Not shown while softball is switched off. |
| `manifest.webmanifest`, `icon-*.png`, `apple-touch-icon.png` | Lets phones add StandPoint to the home screen as an app. |
| `scripts/build_national.py` | Rebuilds the `NATIONAL` (baseball) and `SOFTBALL` lists inside `index.html` from `data/`. Run `python3 scripts/build_national.py`. |

Texas and Oklahoma schools, with coaches, cities and fit notes, are hand-written in `index.html`. Search for `var SCHOOLS = [`.

## Where things live in index.html

- `METRICS`, `RANGES`, `LEVELS`: level benchmarks (GetRecruited, June 2026; JUCO from NCSA).
- `TASKS`: recruiting checklist by grade.
- `PROGRAMS`, `SPEED`, `EXINFO`: lift days, speed days, and the exercise library (how, cue, control, what to log).
- `SCHOOLS`, `NATIONAL`, `SOFTBALL`, `JUCO_PARTIAL`, `BORDERS`, `REGION_OF`: the school directory and the range logic.
- `PLANS`, `renderPlans`, `renderClub`, `coachingCard`, `renderCoachInbox`, `renderCollegeSearch`, `renderInstall`: the More screens.
- `render*` functions: one per screen.

## Privacy and legal notes for the real build

- Most users are minors. Collect only what recruiting needs. Never show a minor's phone number or home address publicly. Get a parent's consent and give parents control.
- **COPPA** applies to users under 13; the plan is 13 and up only.
- **Texas SCOPE Act (HB 18):** a 2023 Texas law on minors' data, partly blocked in federal court, with an appeal ongoing (rehearing granted Oct 2026). Have a Texas attorney review before launch.
- The lift programs are original. They're modeled on the structure of college programs but don't copy any school's sheets, logos or players' data. Get permission before naming a college program.
- Keep this repository **private**: it is the product. Add collaborators instead of making it public.

## Next steps for a developer

1. Pick a stack for the real app: a web app that installs on phones first, then App Store and Google Play.
2. Add accounts (player, parent, coach, club admin), a database, and sync. Move the school directory into the database.
3. Turn the More demos into real features: Stripe subscriptions with webhooks, club rosters joined by code, and video upload for coach reviews.
4. Finish the data: the remaining junior colleges and coach staffs nationwide, refreshed every year.
5. Verified numbers: link showcase and device results, or require proof (video) for coach-facing views.
6. Down the road: softball, then other sports (softball level ranges and programs nationwide).
7. Down the road, once there's a large base of players: college-coach accounts that colleges pay for, to search verified players (with player and parent consent, after a lawyer's review).
