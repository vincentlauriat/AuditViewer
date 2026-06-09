import sys, json, os, time
out = os.environ.get("AUDIT_OUT") or os.path.dirname(os.path.abspath(__file__))
qid, text, opts_csv = sys.argv[1], sys.argv[2], sys.argv[3]
timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 1800  # 30 min
options = []
for tok in opts_csv.split("|"):
    val, _, lab = tok.partition("=")
    options.append({"value": val, "label": lab or val})
q = {"v": 1, "id": qid, "text": text, "options": options}
qp, ap = os.path.join(out, "_question.json"), os.path.join(out, "_answer.json")
json.dump(q, open(qp, "w", encoding="utf-8"), ensure_ascii=False)
deadline = time.time() + timeout
while time.time() < deadline:
    if os.path.exists(ap):
        try:
            ans = json.load(open(ap, encoding="utf-8"))
        except Exception:
            time.sleep(0.3); continue  # écriture partielle, on réessaie
        os.remove(ap)
        if os.path.exists(qp):
            os.remove(qp)  # question consommée
        print(ans.get("value", ""))
        sys.exit(0)
    time.sleep(0.5)
# timeout → on retire la question et on signale l'expiration
if os.path.exists(qp):
    os.remove(qp)
print("__timeout__")
