#!/usr/bin/env bash
# Installe le skill audit-report dans ~/.claude/skills
# Par défaut : crée un lien symbolique vers ce dépôt (source de vérité unique).
# Avec --copy : copie le skill (utile pour une machine sans le dépôt cloné en permanence).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/skills/audit-report"
DEST_DIR="${HOME}/.claude/skills"
DEST="$DEST_DIR/audit-report"
MODE="symlink"

[[ "${1:-}" == "--copy" ]] && MODE="copy"

if [[ ! -f "$SRC/SKILL.md" ]]; then
  echo "✗ Introuvable : $SRC/SKILL.md" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

# Sauvegarder une éventuelle installation existante non liée
if [[ -e "$DEST" && ! -L "$DEST" ]]; then
  BACKUP="$DEST.backup.$(date +%Y%m%d%H%M%S)"
  echo "→ Sauvegarde de l'installation existante : $BACKUP"
  mv "$DEST" "$BACKUP"
elif [[ -L "$DEST" ]]; then
  rm "$DEST"
fi

if [[ "$MODE" == "copy" ]]; then
  cp -R "$SRC" "$DEST"
  echo "✓ Skill copié vers $DEST"
else
  ln -s "$SRC" "$DEST"
  echo "✓ Symlink créé : $DEST → $SRC"
fi

echo "→ Teste avec : /audit-report --help"
