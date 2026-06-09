import sys, json, os
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
p = os.path.join(out, "_control.json")
if os.path.exists(p):
    try:
        c = json.load(open(p, encoding="utf-8"))
    except Exception:
        c = {}
    os.remove(p)  # consommé
    act = c.get("action", "")
    if act:
        print(act + ((":" + c["dimension"]) if c.get("dimension") else ""))
