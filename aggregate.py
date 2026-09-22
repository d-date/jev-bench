import glob
import statistics as stats
import sys

directory = sys.argv[1]
runs = sorted(glob.glob(f"{directory}/run*.out"))
if not runs:
    raise SystemExit(f"no run*.out files in {directory}")

summary = {}
per_sample = {}
truth = {}
stressor = {}
changes = {"fixed": 0, "broke": 0}

for path in runs:
    for line in open(path).read().splitlines():
        fields = [part.strip() for part in line.split("|")]
        if len(fields) > 5 and fields[1][:2] in ("A.", "B.", "C.", "D."):
            arm = fields[1][0]
            summary.setdefault(arm, []).append(
                (int(fields[2].rstrip("%")), int(fields[3].rstrip("%")),
                 float(fields[4].rstrip("s")))
            )
        if len(fields) < 10 or not fields[1].startswith(("s0", "s1")):
            continue
        sid, stress, expected = fields[1:4]
        truth[sid] = expected
        stressor[sid] = stress
        cells = {"A": fields[4], "B": fields[6], "C": fields[7]}
        if len(fields) >= 13:
            cells["D"] = fields[10]
            before = fields[9] != "—" and "×" not in fields[9]
            after = fields[10] != "—" and "×" not in fields[10]
            if not before and after:
                changes["fixed"] += 1
            if before and not after:
                changes["broke"] += 1
        for arm, cell in cells.items():
            per_sample.setdefault((arm, sid), []).append(cell != "—" and "×" not in cell)

labels = {
    "A": "A. Jev 単体（日本語のまま）",
    "B": "B. Foundation Models 単体",
    "C": "C. FM で英語に整形 → Jev",
    "D": "D. Jev の判定 → FM が最終判断",
}
arms = [arm for arm in "ABCD" if arm in summary]
n = len(runs)
print(f"=== {n} 回の平均（12 件の日本語問い合わせ）===\n")
print("| 構成 | 部署の正解率 | 振れ幅 | 緊急度のラベル一致率 | 振れ幅 | 平均レイテンシ/件 |")
print("|---|---|---|---|---|---|")
for arm in arms:
    values = summary[arm]
    if len(values) != n:
        raise SystemExit(f"{arm} is missing from one or more runs")
    dept = [row[0] for row in values]
    urgency = [row[1] for row in values]
    latency = sum(row[2] for row in values) / (12 * n)
    print(
        f"| {labels[arm]} | {stats.mean(dept):.0f}% | {min(dept)}–{max(dept)}% "
        f"| {stats.mean(urgency):.0f}% | {min(urgency)}–{max(urgency)}% | {latency:.2f}s |"
    )

print(f"\n=== サンプルごとの正答回数（{n} 回中）===\n")
print("| ID | 難所 | 正解 | " + " | ".join(arms) + " |")
print("|---|---|---|" + "---|" * len(arms))
for sid in sorted(truth):
    cells = []
    for arm in arms:
        outcomes = per_sample[(arm, sid)]
        count = sum(outcomes)
        label = f"{count}/{n}"
        cells.append(f"**{label}**" if count < n else label)
    print(f"| {sid} | {stressor[sid]} | {truth[sid]} | " + " | ".join(cells) + " |")

if "D" in arms:
    print(f"\nD: FM corrected {changes['fixed']} Jev classifications and changed "
          f"{changes['broke']} correct Jev classifications to incorrect ones.")
