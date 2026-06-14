# Contributing to AuditViewer

Thanks for your interest! Contributions of all kinds are welcome — bug reports, ideas, documentation, and code. This guide gets you set up.

*🇫🇷 Une version française suit ci-dessous.*

---

## Ways to contribute

- **Report a bug** — open an issue with steps to reproduce, what you expected, and what happened.
- **Suggest a feature** — open an issue describing the use case (the *why* matters more than the *how*).
- **Improve the docs** — typos, clarity, missing examples; docs live in [`docs/`](docs/) (English) and [`docs/fr/`](docs/fr/) (French).
- **Submit code** — see the setup below, then open a pull request.

## Repository layout

| Folder | What it is | Stack |
|---|---|---|
| `skills/audit-report/` | The AI audit skill | Markdown skill spec |
| `web/` | Web viewer & control UI | Node + React + Vite |
| `mac/` | Native macOS app | Swift / SwiftUI |
| `docs/` | User documentation | Markdown (EN + FR) |

The three apps communicate through a versioned **machine contract** — read [ARCHITECTURE.md](ARCHITECTURE.md) before changing any output format.

## Local setup

**Skill** — `./install.sh` (or `--gemini`), then `/audit-report --help` in your AI assistant.

**Web viewer**
```bash
cd web
npm install
npm run dev          # backend :3001 + frontend :5173
npm run typecheck    # before submitting
```

**macOS app**
```bash
cd mac
swift build          # quick compile check
./build.sh           # full .app bundle (dev)
```
For the distributable build (XcodeGen + Sparkle), see [`mac/RELEASE.md`](mac/RELEASE.md).

## Pull request checklist

- [ ] The relevant build/typecheck passes (`npm run typecheck` for web, `swift build` for mac).
- [ ] If you changed the skill's output format, you updated the contract in [ARCHITECTURE.md](ARCHITECTURE.md) **and** the readers in `web/` and `mac/`.
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`…).
- [ ] Docs updated if behavior changed (EN and, ideally, FR).

## Conventions

- **Code comments and UI labels** in the macOS app are in **French** (existing convention). User-facing docs are bilingual (English primary).
- Keep the machine contract **versioned**: any breaking change to the JSON artifacts bumps `"v"`.
- No new runtime dependencies for the rendering bundles (offline, vanilla JS).

## Code of conduct

Be respectful and constructive. Assume good faith.

---

# Contribuer à AuditViewer 🇫🇷

Merci de votre intérêt ! Toutes les contributions sont les bienvenues — rapports de bugs, idées, documentation, code.

## Comment contribuer

- **Signaler un bug** — ouvrez une *issue* avec les étapes de reproduction, le comportement attendu et le comportement observé.
- **Proposer une fonctionnalité** — ouvrez une *issue* décrivant le cas d'usage (le *pourquoi* compte plus que le *comment*).
- **Améliorer la doc** — la documentation est dans [`docs/`](docs/) (anglais) et [`docs/fr/`](docs/fr/) (français).
- **Proposer du code** — suivez la mise en place ci-dessus (section anglaise), puis ouvrez une *pull request*.

## Mise en place

Voir la section anglaise « Local setup » : skill via `./install.sh`, viewer web via `npm install && npm run dev`, app macOS via `swift build` / `./build.sh`. Build distribuable : [`mac/RELEASE.md`](mac/RELEASE.md).

## Avant d'ouvrir une PR

- Le build/typecheck concerné passe (`npm run typecheck` pour le web, `swift build` pour le mac).
- Toute modification du format de sortie du skill est répercutée dans [ARCHITECTURE.md](ARCHITECTURE.md) **et** chez les lecteurs `web/` et `mac/`.
- Commits au format [Conventional Commits](https://www.conventionalcommits.org/).
- Documentation mise à jour si le comportement change.

## Conventions

- Les **commentaires de code et libellés d'UI** de l'app macOS sont en **français** (convention existante).
- Le contrat machine reste **versionné** : tout changement cassant des artefacts JSON incrémente `"v"`.
- Pas de nouvelle dépendance d'exécution pour les bundles de rendu (hors-ligne, JS vanilla).
