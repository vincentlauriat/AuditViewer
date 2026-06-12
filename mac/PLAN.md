# PLAN — Réalignement AuditViewer sur le contrat machine v1 du skill `audit-report`

Objectif : remettre l'app en état de marche avec le nouveau **contrat machine v1** du skill
(stabilisé dans le dépôt `SkillAuditReport`). Référence canonique du contrat :
`/Users/vincent/Documents/GitHub/SkillAuditReport/PLAN.md` et
`/Users/vincent/Documents/GitHub/SkillAuditReport/auditviewer/shared/contract.ts`
(implémentation web de référence, correcte).

Contraintes projet (cf. `CLAUDE.md`) : tout en français (code/UI), Swift 6 strict concurrency
(`AuditStore` est `@MainActor @Observable`), build via `swift build` puis `./build.sh`, style existant
(`// MARK:`, commentaires FR). Ne pas toucher au bundle `web/` partagé avec MarkdownViewer.

## Schémas v1 de référence (artefacts dans `audit-{slug}/`)

`_events.jsonl` (1 objet JSON/ligne) — champs communs `v` (=1), `ts` (ISO8601 UTC), `type`. Types et payloads :
- `audit_start` `{subject, depth, mode, options, output_dir}`
- `phase_start` / `phase_done` `{phase, label}` — phases : recon, research, factcheck, swot, summary, assembly, finalize
- `dimension_start` / `dimension_done` `{dimension, label, status?, sources_count?, summary?}` — dimensions : historique, marche, technique, tarification, concurrence, financier, futur, esg, rh
- `progress` `{done, total, pct}`
- `search` `{query}` · `source` `{url, title, tag}` · `file_written` `{file}`
- `question` `{id}` · `answer` `{id, value}`
- `error` `{phase?, dimension?, message}`
- `audit_complete` `{files_count, sources_count, status}` · `audit_canceled` `{reason}`

`_manifest.json` : `{v, subject, subject_type, slug, output_dir, audit_date, depth, mode, options[],
status: "complete"|"partial"|"canceled", dimensions:[{key,file,status,sources_count}],
files:[{name,kind}], sources_count, data_file, sources_file, report_file}`.

`_sources.json` : `{v, sources:[{id, url, title, tag:"Officielle"|"Analyste"|"Presse", date, dimensions[], stale}]}`.

`_data.json` : `{v, subject, subject_type, as_of, kpis:[{key,label,value,unit,period,source_id,estimated}],
financials?, market?, sources_count?, competitors_count?}`.

`_question.json` : `{v, id, text, options:[{value,label}]}` · `_answer.json` : `{v, id, value}` (atomique).
`_control.json` (UI→skill) : `{v, action:"cancel"|"pause"|"resume"|"rerun", dimension?}`.

## P0 — Réparer le suivi live des events (BLOQUANT)

Cause : `Sources/AuditEvent.swift` attend `t` (v1 = `ts`) et son `enum EventType` strict ne contient que
les anciens types → `readNewEvents` (AuditStore) ignore **tous** les events v1.

1. **Réécrire `AuditEvent.swift`** :
   - Champ horodatage = `ts` (décoder `ts`, accepter `t` en repli pour compat ascendante). Ajouter `v: Int?`.
   - Couvrir TOUS les types v1 ci-dessus. Rendre le décodage du type **tolérant** : un type inconnu ne doit
     PAS faire échouer le décodage de la ligne (ex. `type` en `String` + enum calculé optionnel, ou
     `init(from:)` qui mappe l'inconnu sur un cas `.unknown`).
   - Ajouter les champs payload : `phase, dimension, label, status, sourcesCount (sources_count),
     summary, done, total, pct, value, subject, depth, mode, options, outputDir (output_dir), reason,
     query, url, title, file, id, message` (tous optionnels, `CodingKeys` snake_case).
   - Garder `AuditQuestion`/`AuditAnswer` ; ajouter `v: Int = 1` à `AuditAnswer` (cosmétique de cohérence).
2. **`AuditStore.applyEvent`** : gérer les nouveaux types — `progress` (mettre à jour une progression
   chiffrée 0–100 depuis `pct`), `dimension_done` (marquer la dimension/section faite, incrémenter), 
   `question` (déclencher `checkForQuestion`), `audit_canceled` (stop + reload comme `audit_complete`),
   `error` (journaliser). Conserver `file_written`/`audit_complete`.
3. **Progression** : adapter `LiveProgressView`/`AuditProgressView` pour consommer la progression chiffrée
   (`progress.pct`) et l'état par dimension issus des events v1 (au lieu des anciens `step_*`). Lire le code
   actuel pour voir comment `eventLog` alimente ces vues et réaligner.

Critère P0 : pendant un audit `--app-mode`, la timeline et la barre de progression vivent à nouveau.

## P1 — Fiabiliser le lancement (`AuditStore.runAudit` + slug)

1. **Passer `--output <dir>` explicite** au skill (ne plus dépendre du cwd + `findNewAuditDir`). Construire
   `outputDir = <researchRoot>/audit-<slug>` et l'ajouter au prompt : 
   `/audit-report "<subject>" <flags> --app-mode --output "<outputDir>"`.
2. **Quoter le sujet** dans le prompt (sujet entre guillemets, guillemets internes échappés) — évite
   l'injection d'arguments et gère les espaces/accents. (cf. le correctif équivalent côté web.)
3. **Slug déterministe aligné v1** : remplacer le `lowercased()` simpliste par la règle v1 — normalisation
   NFKD → ASCII (retrait des diacritiques) → tout caractère non alphanumérique → `-` → compression/trim des
   tirets → minuscules → défaut `sujet`. Réutiliser ce slug pour le dossier ET pour retrouver l'audit.
   Aligner `findNewAuditDir`/`subjectFromDir` en conséquence.
4. **Surveiller le bon dossier** : `startWatchingEvents` doit pointer sur `outputDir` (déterministe), plus
   besoin de deviner via `findNewAuditDir`.

## P2 — Exploiter les nouveaux artefacts

1. **`_manifest.json`** : nouveau modèle `AuditManifest` (Codable, snake_case). Dans `loadAuditDir`, si
   `_manifest.json` présent : l'utiliser pour le **statut** (complete/partial/canceled), la liste des
   **dimensions** (et leur fichier/sources_count), les **options**. Fallback : comportement actuel (scan
   des `.md`) si absent — indispensable pour les audits legacy de `~/Documents/Research`.
2. **`_sources.json`** : nouveau modèle `SourcesFile`/`AuditSource`. `generateSourcesMarkdown` lit
   `_sources.json` s'il existe (rendu : tableau avec tag [Officielle]/[Analyste]/[Presse], date, ⚠️ si
   `stale`, dimensions citantes) ; sinon conserve le scan regex actuel des `.md`.
3. **`_data.json` `kpis[]`** : `generateDataMarkdown` détecte le schéma v1 (présence de `kpis`) et rend un
   **tableau KPI dédié** (Libellé | Valeur+unité | Période | officiel/estimé), au lieu du `renderJSON`
   récursif générique. Garder `renderJSON` en repli pour les `_data.json` non-v1 (legacy).
4. (Optionnel) **`_control.json`** : permettre l'annulation propre d'un audit en cours en écrivant
   `{v:1, action:"cancel"}` (en plus de tuer le `Process`), pour que le skill s'arrête proprement.

## Validation
- `swift build` vert, puis `./build.sh` vert, `open build/AuditViewer.app` démarre.
- Affichage non régressé sur un audit legacy de `~/Documents/Research` (ex. `audit-voltalia`).
- Idéalement : un audit `--app-mode` réel (quick) suivi en live (P0) — sinon, fabriquer un `_events.jsonl`
  v1 de test et vérifier le décodage/progression.

## Décisions déléguées (défauts retenus, modifiables)
- Type inconnu d'event → cas `.unknown` non bloquant (ne casse pas le flux).
- `_options.json` (persistance locale des options par l'app) : conservé tel quel (le skill l'ignore).
- `_control.json` (P2.4) : implémenté a minima (cancel) puisque périmètre P0+P1+P2 retenu.
