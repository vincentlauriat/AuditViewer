# Publier une release de l'app macOS

Pipeline de distribution : build Release → signature Developer ID → notarisation Apple →
DMG habillé → signature Sparkle → `appcast.xml` → GitHub Release. Calqué sur les apps
WifiManager / MarkdownViewer (mêmes identité de signature et clé Sparkle).

## Prérequis (une fois par machine)

| Élément | Détail |
|---|---|
| **XcodeGen** | `brew install xcodegen` |
| **Certificat Developer ID Application** | `Developer ID Application: Vincent LAURIAT (KFLACS69T9)` dans le trousseau |
| **Profil de notarisation** | Profil `notarytool` nommé `AppliMacVincentGithub` (créé via `xcrun notarytool store-credentials`) |
| **Clé EdDSA Sparkle** | Dans le trousseau, compte `MarkdownViewer` (partagée entre les apps ; la clé publique est `SUPublicEDKey` dans `project.yml`) |
| **GitHub CLI** | `gh` authentifié sur le dépôt `vincentlauriat/AuditViewer` |

Variables surchargeables : `SIGNING_IDENTITY`, `NOTARY_PROFILE`, `SPARKLE_ACCOUNT`, `GH_REPO`.

## Étapes

1. **Bumper la version** dans `project.yml` (`MARKETING_VERSION` et, si besoin, `CURRENT_PROJECT_VERSION`).
2. **Construire + signer + notariser + DMG + appcast** :
   ```bash
   cd mac
   ./Scripts/release.sh 1.0.0
   ```
   Produit `AuditViewer-1.0.0.dmg` (signé, notarisé, agrafé) et met à jour `appcast.xml`.
3. **Publier la GitHub Release** (le `.dmg` doit être attaché — c'est l'URL référencée par l'appcast) :
   ```bash
   gh release create v1.0.0 ./AuditViewer-1.0.0.dmg --title "v1.0.0" --notes "Notes de version…"
   ```
4. **Pousser l'appcast** (c'est lui que les apps installées interrogent) :
   ```bash
   git add appcast.xml && git commit -m "chore: appcast v1.0.0" && git push
   ```

## Comment l'auto-update fonctionne

- L'app embarque `SUFeedURL` → `https://raw.githubusercontent.com/vincentlauriat/AuditViewer/main/appcast.xml`.
- Au lancement (et une fois par jour), Sparkle lit l'appcast, compare les versions, et propose la mise à jour.
- L'utilisateur peut aussi déclencher la vérification via **AuditViewer ▸ Rechercher les mises à jour…**.
- Chaque DMG est signé EdDSA : Sparkle refuse une mise à jour dont la signature ne correspond pas à `SUPublicEDKey`.

## Notes

- `Info.plist` est **généré** par XcodeGen depuis `project.yml` — ne pas l'éditer à la main.
- `AuditViewer.xcodeproj`, `build/`, `*.dmg` et `.sparkle-tools/` sont gitignorés (régénérables).
