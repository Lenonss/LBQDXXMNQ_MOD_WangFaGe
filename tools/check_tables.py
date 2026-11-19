import pathlib
import re

p = pathlib.Path("docs/属性速查.md")
rows = [l for l in p.read_text(encoding="utf-8").splitlines() if l.startswith("| `")]
bad = []
for line in rows:
    body = line.replace("\\|", "\x00")
    if body.count("|") > 9:
        bad.append(line)
print("rows:", len(rows), "bad:", len(bad))
for b in bad[:3]:
    print(b[:160])

q = pathlib.Path("docs/官方字段统计.md")
bad2 = []
for line in q.read_text(encoding="utf-8").splitlines():
    if line.startswith("| `"):
        body = line.replace("\\|", "\x00")
        if body.count("|") > 3:
            bad2.append(line)
print("static bad:", len(bad2))
for b in bad2[:3]:
    print(b[:160])
