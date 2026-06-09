import sys, json, os, datetime
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
a = sys.argv[1:]
ev = {"v": 1,
      "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
      "type": a[0] if a else "unknown"}
i = 1
while i < len(a):
    ev[a[i].lstrip("-")] = a[i + 1] if i + 1 < len(a) else ""
    i += 2
with open(os.path.join(out, "_events.jsonl"), "a", encoding="utf-8") as f:
    f.write(json.dumps(ev, ensure_ascii=False) + "\n")
