# TODOS — Contrat machine v1 (P0 + P1)

## P0 — Contrat machine
- [x] 1. Helper `_emit.py` (émission fiable via argv)
- [x] 2. `_events.jsonl` versionné + émission par dimension en parallel
- [x] 3. `_control.json` (cancel/pause/resume/rerun) + points de contrôle
- [x] 4. Cycle de vie `_question.json`/`_answer.json` (atomique, timeout 30 min → cancel)
- [x] 5. `_manifest.json` final canonique
- [x] 6. `_sources.json` + `_data.json` générique (kpis[])

## P1 — Bugs & cohérence
- [x] 7. Années dynamiques dans les requêtes
- [x] 8. Assemblage conditionnel du rapport
- [x] 9. Mode update en app-mode
- [x] 10. Conflits d'options (`--brief` exclusif)
- [x] 11. Slug déterministe
- [x] 12. Numérotation à trous documentée (manifest = source de vérité)

## Validation
- [x] Snippets Python valides (py_compile + smoke test slug/emit/ctl/ask OK)
- [x] Émission JSONL robuste aux apostrophes/accents (lignes JSON valides)
- [ ] Commit + PR sur feat/app-mode-contract

## P2 — Robustesse
- [x] `datetime.utcnow()` → `datetime.now(timezone.utc)` (fait dans _emit.py)
- [x] Estimation coût/temps pré-lancement (résumé de confirmation)
- [x] `--verbose` clarifié en --mode parallel (limite documentée)
- [x] Confirmation app-mode unifiée sur `_ask.py` (fin du timeout 10 min codé en dur)

## Suite (hors périmètre de cette PR)
- AuditViewer : runner headless + UI de visualisation/pilotage
- Test bout-en-bout : `/audit-report Notion --depth quick`
