#!/usr/bin/env python3
"""StandPoint workout library workbook, built from the app's own data so the sheet matches what players see."""
import json, sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter

D = json.load(open(sys.argv[1], encoding="utf-8"))
OUT = sys.argv[2]

NAVY, GOLD, CREAM, FILL, GRAY = "14213D", "C9A227", "FBF8F1", "FFF2CC", "6B7280"
F = lambda **k: Font(name="Arial", size=k.pop("size", 10), **k)
HEAD = PatternFill("solid", fgColor=NAVY)
YEL = PatternFill("solid", fgColor=FILL)
BAND = PatternFill("solid", fgColor=CREAM)
thin = Side(style="thin", color="D9D9D9")
BOX = Border(bottom=thin)
WRAP = Alignment(wrap_text=True, vertical="top")
STATUS = '"Team to approve,Approved,Change it,Remove"'

wb = Workbook()


def sheet(title, headers, widths, rows, fill_cols=(), status_col=None, top=None):
    ws = wb.create_sheet(title)
    r0 = 1
    if top:
        for line in top:
            ws.cell(r0, 1, line).font = F(bold=r0 == 1, size=12 if r0 == 1 else 10, color=NAVY if r0 == 1 else "000000")
            r0 += 1
        r0 += 1
    for c, h in enumerate(headers, 1):
        x = ws.cell(r0, c, h); x.font = F(bold=True, color="FFFFFF"); x.fill = HEAD; x.alignment = Alignment(wrap_text=True, vertical="center")
    ws.row_dimensions[r0].height = 30
    for i, row in enumerate(rows):
        r = r0 + 1 + i
        for c, v in enumerate(row, 1):
            x = ws.cell(r, c, v); x.font = F(); x.alignment = WRAP; x.border = BOX
            if c in fill_cols: x.fill = YEL
    for c, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(c)].width = w
    ws.freeze_panes = ws.cell(r0 + 1, 1)
    last = r0 + max(len(rows), 1)
    ws.auto_filter.ref = "A%d:%s%d" % (r0, get_column_letter(len(headers)), last)
    if status_col:
        dv = DataValidation(type="list", formula1=STATUS, allow_blank=True)
        ws.add_data_validation(dv); col = get_column_letter(status_col); dv.add("%s%d:%s%d" % (col, r0 + 1, col, last + 40))
    return ws, r0


def item_text(it, ph):
    if isinstance(it, list):
        return it[ph - 1]
    return it


def ex_match(t):
    t = str(t or "").lower()
    for e in D["EXINFO"]:
        if e[0] in t:
            return e[1]
    return None


used = {}
def mark(t, where):
    n = ex_match(t)
    if n:
        used.setdefault(n, [])
        if where not in used[n]: used[n].append(where)

BN = D["BLOCK_NAMES"]
blk = lambda t: BN[t].split(":")[0].split(",")[0]

# ---------- Lift days ----------
lift_rows = []
for days in ["2", "3", "4"]:
    for si, sess in enumerate(D["PROGRAMS"][days]):
        for b in sess["blocks"]:
            if b["t"] == "main":
                L = D["LIFTS"][b["lift"]]
                for v in L["vars"]: mark(v["n"], "Main lift")
                lift_rows.append([days + "-day", sess["name"], "Main lift", L["vars"][0]["n"] + " (sets on the Main lift sets tab)", "Same", "Team to approve", ""])
                continue
            for it in b["items"]:
                p1, p2 = item_text(it, 1), item_text(it, 2)
                for t in (p1, p2):
                    if t: mark(t, "Lifts " + days + "-day")
                lift_rows.append([days + "-day", sess["name"], blk(b["t"]), p1 or "(not in phase 1)", "Same" if p2 == p1 else (p2 or "(not in phase 2)"), "Team to approve", ""])

# ---------- Speed days ----------
NOV6_SPEED = {"Speed C · Side to side and curves", "Tempo · Conditioning runs"}
speed_rows = []
for sess in D["SPEED"]:
    for b in sess["blocks"]:
        for it in b["items"]:
            p1, p2 = item_text(it, 1), item_text(it, 2)
            for t in (p1, p2):
                if t: mark(t, "Speed: " + sess["name"].split(" · ")[0])
            speed_rows.append([sess["name"], blk(b["t"]), p1 or "(not in phase 1)", "Same" if p2 == p1 else (p2 or "(not in phase 2)"),
                               "Alejandro's Nov 6 sheets, rewritten" if sess["name"] in NOV6_SPEED else "StandPoint base", "Team to approve", ""])

# ---------- Goal work ----------
GOALS = {"hit": "Hit harder", "speed": "Get faster", "arm": "Throw harder", "pitch": "Pitch better", "strength": "Get stronger", "gain": "Put on muscle", "lean": "Get leaner", "recruit": "Get recruited"}
EQ = {"none": "Nothing", "band": "A band", "mb": "Med ball", "gym": "Dumbbells or kettlebells", "bar": "Full gym (bar, cable, bench)"}
goal_rows = []
for g, lst in D["AUTO_GOAL"].items():
    if not lst:
        goal_rows.append([GOALS[g], "", "No lift work. Recruiting help comes from the Recruit and Schools tabs.", "", "", "", ""]); continue
    for i, x in enumerate(lst, 1):
        mark(x["t"], "Goal work: " + GOALS[g])
        goal_rows.append([GOALS[g], i, x["t"], EQ[x["eq"]], "Yes" if x.get("arm") else "No", "Team to approve", ""])

# ---------- Hitting and arm care ----------
ha_rows = []
for key, who, days in [("power", "Hitters who picked Hit harder", "3"), ("base", "Every other position player", "2")]:
    H = D["AUTO_HIT"][key]
    n = max(len(H["items"]), len(H["alt"]))
    for i in range(n):
        a = H["items"][i] if i < len(H["items"]) else ""
        c = H["alt"][i] if i < len(H["alt"]) else ""
        for t in (a, c):
            if t: mark(t, "Hitting: " + H["name"])
        ha_rows.append([H["name"], who if i == 0 else "", days if i == 0 else "", a, c, "Team to approve", ""])
AC = D["AUTO_ARMCARE"]
for i, t in enumerate(AC["items"]):
    mark(t, "Arm care")
    ha_rows.append([AC["name"], "Every player whose arm doesn't hurt" if i == 0 else "", "3" if i == 0 else "", t, "Same", "Team to approve", ""])

# ---------- Exercises ----------
ex_rows = []
LOG = {"w": "Weight × reps", "mb": "Ball weight × reps", "box": "Box height × reps", "t": "Seconds", "none": "Check it off"}
for e in D["EXINFO"]:
    key, name, log, how, cue, ctl, src = e
    ex_rows.append([name, key, LOG.get(log, log), how, cue, ctl, "; ".join(used.get(name, [])) or "Library only, not in a session yet", src, "Team to approve", "", "", ""])

# ---------- Read me ----------
ws = wb.active; ws.title = "Read me"
lines = [
    ("StandPoint workout library", "title"),
    ("Every move and session the app gives players, pulled straight from the app on Nov 6, 2026. Starter content: the team approves it before the pilot.", ""),
    ("", ""),
    ("How to use it", "h"),
    ("1. Go through each tab. Yellow columns are yours to fill in: Status, Approved by, Demo video link and Notes.", ""),
    ("2. Status options: Team to approve, Approved, Change it, Remove. For Change it, write the change in Notes.", ""),
    ("   Example: Status = Change it · Notes = \"Freshmen do 2 × 3, not 3 × 3\" · Demo video link = a link to your own demo.", ""),
    ("3. The Throwing program tab is blank on purpose. Coaches write it. StandPoint never makes up throwing volumes.", ""),
    ("4. Send the finished file back and the changes go into the app.", ""),
    ("", ""),
    ("Rules the app already follows", "h"),
    ("Coaches' plans always come first: club, then team, then one player. The automatic plan only fills gaps, and a coach can remove any part or turn it off.", ""),
    ("Goal work: his top 2 goals, the first 2 moves per goal that fit his equipment, 4 moves at most, added before the finish of each lift.", ""),
    ("If his arm hurts when he throws: no throwing routine, no throws or arm-care lifts, and a note to see a doctor or athletic trainer.", ""),
    ("Pitchers get no automatic hitting routine. Loads are by feel, never a % of a max. Re-test and rebuild every 4 weeks.", ""),
    ("", ""),
    ("Where things stand", "h"),
]
for i, (t, kind) in enumerate(lines, 1):
    c = ws.cell(i, 1, t)
    c.font = F(bold=True, size=14, color=NAVY) if kind == "title" else F(bold=True, size=11, color=NAVY) if kind == "h" else F()
r = len(lines) + 1
ws.cell(r, 1, "Status").font = F(bold=True, color="FFFFFF"); ws.cell(r, 1).fill = HEAD
ws.cell(r, 2, "Exercises").font = F(bold=True, color="FFFFFF"); ws.cell(r, 2).fill = HEAD
ws.cell(r, 3, "Lift days").font = F(bold=True, color="FFFFFF"); ws.cell(r, 3).fill = HEAD
ws.cell(r, 4, "Speed days").font = F(bold=True, color="FFFFFF"); ws.cell(r, 4).fill = HEAD
STAT_TABS = []  # filled after the tabs exist
status_row0 = r + 1
for j, stt in enumerate(["Team to approve", "Approved", "Change it", "Remove"]):
    ws.cell(status_row0 + j, 1, stt).font = F()
ws.cell(status_row0 + 4, 1, "Total rows").font = F(bold=True)
ws.cell(status_row0 + 6, 1, "Counts update as you change Status on each tab.").font = F(italic=True, color=GRAY)
ws.column_dimensions["A"].width = 22
for col in "BCD": ws.column_dimensions[col].width = 14

# ---------- Tabs ----------
sheet("Exercises", ["Exercise", "App matches this text", "What he logs", "How to do it", "Cue", "Control the weight", "Used in", "Source", "Status", "Approved by", "Demo video link", "Notes"],
      [26, 18, 14, 52, 30, 34, 34, 20, 15, 14, 22, 30], ex_rows, fill_cols=(9, 10, 11, 12), status_col=9)
sheet("Lift days", ["Program", "Session", "Block", "Phase 1 (weeks 1–4)", "Phase 2 (weeks 5–8)", "Status", "Notes"], [10, 34, 16, 48, 48, 15, 30], lift_rows, fill_cols=(6, 7), status_col=6)
rx_rows = []
for season, label in [("off", "Off-season"), ("in", "In-season")]:
    for ph in ["1", "2"]:
        rx_rows.append([label, "Phase " + ph] + D["MAIN_RX"][season][ph] + [""])
sheet("Main lift sets", ["Season", "Phase", "Week 1", "Week 2", "Week 3", "Week 4 (lighter)", "Notes"], [14, 10, 10, 10, 10, 16, 40], rx_rows, fill_cols=(7,),
      top=["Main lift sets × reps", "Squat, bench or trap-bar deadlift. Players pick a weight they could lift 2 more times with good form, and add 5–10 lb when every rep looks the same."])
sheet("Speed days", ["Session", "Block", "Phase 1 (weeks 1–4)", "Phase 2 (weeks 5–8)", "Source", "Status", "Notes"], [30, 16, 48, 48, 24, 15, 30], speed_rows, fill_cols=(6, 7), status_col=6,
      top=["Speed days", "2 speed days: A and B. 3 days: A, C, then B. A player who picked Get leaner gets Tempo for his last speed day."])
sheet("Goal work", ["Goal", "Order", "Move", "Needs", "Skipped if his arm hurts", "Status", "Notes"], [16, 7, 52, 26, 14, 15, 30], goal_rows, fill_cols=(6, 7), status_col=6,
      top=["Goal work added to each lift", "Equipment: No gym = nothing and bands. Some weights at home = adds med ball, dumbbells and kettlebells. Full gym = everything."])
sheet("Hitting and arm care", ["Routine", "Who gets it", "Days a week", "With a cage", "No cage", "Status", "Notes"], [22, 26, 9, 44, 40, 15, 30], ha_rows, fill_cols=(6, 7), status_col=6,
      top=["Automatic hitting and arm-care routines", "Players pick any days. Without a cage, the no-cage version is their list; with one, they can switch to it on a day they can't get to a cage."])

# Throwing program: blank for coaches
ws_t, r0 = sheet("Throwing program", ["Phase", "Week", "Day", "Type", "Distance (ft)", "Throws", "Effort", "Notes"], [8, 7, 8, 16, 13, 9, 12, 44], [],
                 top=["Throwing program: coaches write this", "StandPoint shows a player this program only after your coaches approve it. Until then, players see arm care and \"throw only as your coach directs.\"",
                      "If a player says his arm hurts when he throws, the app gives him no throwing at all and tells him to see a doctor or athletic trainer."])
ex = ["1", "1", "Mon", "Catch play", "60–90", "25", "Easy", "EXAMPLE ROW: replace it with your own program"]
for c, v in enumerate(ex, 1):
    x = ws_t.cell(r0 + 1, c, v); x.font = F(italic=True, color=GRAY); x.alignment = WRAP; x.border = BOX
for rr in range(r0 + 2, r0 + 42):
    for c in range(1, 9):
        x = ws_t.cell(rr, c); x.fill = YEL; x.border = BOX; x.font = F(); x.alignment = WRAP
ws_t.auto_filter.ref = None
dv = DataValidation(type="list", formula1='"Catch play,Long toss,Flat ground,Bullpen,Recovery,Arm care only"', allow_blank=True)
ws_t.add_data_validation(dv); dv.add("D%d:D%d" % (r0 + 2, r0 + 41))
dv2 = DataValidation(type="list", formula1='"Easy,Medium,Hard,Max"', allow_blank=True)
ws_t.add_data_validation(dv2); dv2.add("G%d:G%d" % (r0 + 2, r0 + 41))

N6 = [
    ["4-week lift", "Trap-bar snapdown + squat jump", "Goal work: Get faster (full gym)", "Light bar, by feel. No % of a max."],
    ["4-week lift", "Nordic hamstring", "Goal work: Get faster", "2 × 3, partner holds the feet."],
    ["4-week lift", "Half-kneeling Keiser, cable or band torso rotation", "Goal work: Hit harder", "Band works if there's no cable."],
    ["4-week lift", "Single-leg med-ball slam or pullover throw", "Goal work: Pitch better", "Skipped if his arm hurts."],
    ["4-week lift", "Split-stance single-arm cable or band row", "Goal work: Throw harder", ""],
    ["4-week lift", "Banded KB swing", "Goal work: Get stronger", ""],
    ["4-week lift", "Back extension or reverse hyper", "Goal work: Get stronger (full gym)", ""],
    ["4-week lift", "Tall-plank KB pull-through", "Goal work: Pitch better", ""],
    ["4-week lift", "Med-ball shot-put throw", "Goal work: Hit harder", ""],
    ["4-week lift", "Single-leg mini hurdle hops (stick weeks 1–2, continuous 3–4)", "Already in Lift days (phase 2)", "How-to says stick first, then bounce through."],
    ["4-week lift", "Depth drop to lateral bound", "Speed C, phase 2", ""],
    ["4-week lift", "Box jump, scoop toss, landmine press, chest pass, plyo push-up, face pull, 1-arm row", "Already in Lift days", ""],
    ["4-week lift", "Power squat and power bench % waves, other % loads", "Not used", "College % loads aren't right for high schoolers. The app uses sets by feel."],
    ["4-week lift", "Med-ball adductor squeeze, side plank row, PVC straight-arm overcoming iso", "Not in the app yet", "Team to decide."],
    ["Thanksgiving lift + runs", "Altitude landing × 6", "Speed C, phase 1", "4 per set, 2 sets."],
    ["Thanksgiving lift + runs", "Run warm-up: knee hug, quad pull, toe touch, leg cradle, high knees, straight-leg skip, backward open-hip skip, carioca", "Dynamic warm-up in Speed C and Tempo", ""],
    ["Thanksgiving lift + runs", "Post-work soft tissue and stretch: hamstring floss, seated pretzel, stand-to-squat, low-back rotation, butterfly groin", "Post-work stretch in Speed C and Tempo", ""],
    ["Thanksgiving lift + runs", "Alternating lunge jump", "Goal work: Get faster (4th choice)", ""],
    ["Thanksgiving lift + runs", "55-yard strides × 12", "Tempo, phase 2", "Cut to 4 strides for high schoolers."],
    ["Thanksgiving lift + runs", "10 × 10 accelerations", "Already in Speed A (10-yard starts)", ""],
    ["4-week speed", "Half-kneeling lateral accelerations", "Speed C", ""],
    ["4-week speed", "Curvilinear sprints", "Speed C: curved sprints, like rounding first", ""],
    ["4-week speed", "Backward overhead med-ball throw", "Speed C", ""],
    ["4-week speed", "Extensive tempo: 60-yard tempo runs at 70%, 35 sec rest", "Tempo session", "10 reps in phase 1, 12 in phase 2."],
    ["4-week speed", "Extensive tempo: 100-yard tempo runs", "Not used", "60s fit baseball better. Team can add them."],
    ["4-week speed", "Rudiment series (pogos)", "Tempo warm-up", ""],
    ["4-week speed", "Falling starts, push-up accelerations", "Library only", "Team can add them to Speed A."],
    ["4-week speed", "Buildups, fly-ins, broad jumps", "Already in Speed A and B", ""],
]
sheet("Nov 6 sheets", ["Sheet", "What it had", "Where it is in StandPoint", "What we changed"], [22, 56, 36, 44], N6,
      top=["What came from the three sheets sent Nov 6", "Moves and ideas were rewritten in StandPoint's words. College loads and volumes were left out."])

# Read me counts (live formulas)
tabs = [("B", "Exercises", "I"), ("C", "'Lift days'", "F"), ("D", "'Speed days'", "F")]
for col, tab, sc in tabs:
    for j in range(4):
        ws["%s%d" % (col, status_row0 + j)] = '=COUNTIF(%s!$%s:$%s,$A%d)' % (tab, sc, sc, status_row0 + j)
        ws["%s%d" % (col, status_row0 + j)].font = F()
    ws["%s%d" % (col, status_row0 + 4)] = "=SUM(%s%d:%s%d)" % (col, status_row0, col, status_row0 + 3)
    ws["%s%d" % (col, status_row0 + 4)].font = F(bold=True)

wb.save(OUT)
print("saved", OUT, "exercises", len(ex_rows), "lift rows", len(lift_rows), "speed rows", len(speed_rows), "goal rows", len(goal_rows))
print("unused:", [r[0] for r in ex_rows if r[6].startswith("Library only")])
