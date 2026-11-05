# StandPoint (CommitPath) — prototype

A phone-first recruiting and training app for high school baseball players.
A player enters their profile once, logs numbers over time, and the app shows:

- **StandPoint:** which college level their numbers fit today (Top D1, mid-major D1, D2, D3, JUCO) and the exact gaps to the next level.
- **Train:** a weekly lift and speed schedule, an info button on every exercise, weight logged on every exercise, maxes, strength per pound of body weight, bar speed, jump and sprint tests, and pounds moved.
- **Recruit:** NCAA contact dates by class, a yearly checklist, and email, DM and coach-note templates filled in from the profile.
- **Schools:** about 1,550 baseball programs (every NCAA D1, D2 and D3 program, every NAIA program and about 390 junior colleges nationwide, plus Texas and Oklahoma at every level with coaches), filtered to the range the player picks at sign-up. Each school has a fit badge, senior timing, coaches, a 10-step contact tracker and messages addressed to the chosen coach.
- **Post:** builds an X caption from the player's numbers. The player always taps Post themselves.
- **More** (demos on one device): plans and payments (individual plan, club license, coaching add-on; Stripe Payment Links slot), coach inbox for video reviews with assigned drills, and install-to-home-screen.
- **Two apps, one prototype:** a **Player app** (the six tabs above) and a **Coach app** (More → Coach app, or "I'm a coach" at sign-up). On one device they share data; the real build is two apps with their own logins on one database.
- **Organizations, teams and players:** a club or facility (travel club, training facility like Infinite Hitting, high school program, or showcase) has **teams or coach groups** (a "15U" age group, or "Coach Rivera's hitters"), and each team has its coaches. Players enter the club code at sign-up or under More → Your club, pick their team or coach, and a coach accepts them (or the club accepts automatically).
- **Coach tools added Nov 4 (afternoon):** each player's training log on his coach page (sets, weights, throwing and hitting check-offs); Skills (drills per number) and Fuel (notes) customizable for the club, a team or one player; throwing and hitting days can be "any N days a week" for private training; a next-lesson date the player sees on Home and Train; copy one player's plan to another; a recruiting pipeline (not contacted, reached out, responded, seen or camp, visit, offer, committed) for players and coaches; Instagram handle and caption copy.
- **Players on their own (Nov 4, evening):** Build my plan (8 questions: goals, days, session length, gym, field or cage, lifting experience, pain, recruiting struggles) sets lift and speed days and writes an analysis with goal-by-goal steps and the week laid out. Ask StandPoint answers training and recruiting questions with AI (the page's `sample` capability), with guardrails for teenagers: no weight-loss targets or diets, pain and medical questions go to a doctor or trainer, crisis line 988. Plans adds weekly online coaching; club players' coaching requests go to their club's coaches (Coach app → Team → Coaching requests), players on their own join a waitlist. In the real app, the AI call moves to the server with logging and a usage cap.
- **Plans stack:** lifts, throwing, hitting, season and the coaches' note can be set for the whole club, for a team or group, or for one player. The most specific one wins, so a freshman and a junior never have to share a plan. Players see where each plan comes from and their current focus, and Train always shows a Throwing and hitting card. Team routines can be set for the club or a team. A player can work with several coaches (his team's plus any added on his page); any coach can change his plans, and every change is logged with who made it.
- **Coach app tabs:** Team (roster by team, join requests, activity feed, player page with team, plans, recruiting, nudges and notes), Recruit (every player's schools, contacts, status, next step, posting and schedule; filter by team; messages stay private), Training (plan for club/team/player: lifts with no-gym versions, throwing and hitting with no-field/no-cage versions, who's training, video reviews), Schedule (routine and players' events) and Club (invite, license, teams and groups, coaches).

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
- `PLANS`, `renderPlans`, `coachingCard`, `renderCoachInbox`, `renderCollegeSearch`, `renderInstall`: the More screens.
- `normClub`, `layersOf`, `resolve`, `applyClub`, `clubLiftFor`: the organization model and plan stacking (player → team → club). `renderCoachApp`, `coachRecruitingHTML`, `coachTrainingHTML`, `scopeCard`, `clubLiftsHTML`, `listHTML`, `clubRoutineHTML`, `teamsHTML`, `clubPlayerHTML`, `renderJoin`: the Coach app and joining (`store.app` picks the app).
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
3. Turn the demos into real features: Stripe subscriptions with webhooks, club and coach accounts with players joining by code from their own phones, notifications for nudges, and video upload for coach reviews.
4. Finish the data: the remaining junior colleges and coach staffs nationwide, refreshed every year.
5. Verified numbers: link showcase and device results, or require proof (video) for coach-facing views.
6. Down the road: softball, then other sports (softball level ranges and programs nationwide).
7. Down the road, once there's a large base of players: college-coach accounts that colleges pay for, to search verified players (with player and parent consent, after a lawyer's review).
