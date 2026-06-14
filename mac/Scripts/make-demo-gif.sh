#!/usr/bin/env bash
# Construit un GIF de démonstration (diaporama) à partir des captures du dépôt.
# Nécessite ffmpeg. Sortie : images/demo.gif
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMG="$ROOT/images"
OUT="$IMG/demo.gif"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Canevas et cadence
W=1100; H=688; BG="0x0f172a"; SECS=1.9   # durée par image

# Ordre du diaporama (mix web + macOS)
FRAMES=(
  screenshot-web-summary.png
  screenshot-web-graph.png
  screenshot-web-timeline.png
  screenshot-mac-graph.png
  screenshot-mac-factcheck.png
)

echo "→ Normalisation des images (${W}x${H}, fond sombre)…"
i=0
: > "$TMP/list.txt"
for f in "${FRAMES[@]}"; do
  out=$(printf "$TMP/frame_%02d.png" "$i")
  ffmpeg -y -loglevel error -i "$IMG/$f" \
    -vf "scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:color=$BG,setsar=1" \
    -frames:v 1 "$out"
  echo "file '$out'"      >> "$TMP/list.txt"
  echo "duration $SECS"   >> "$TMP/list.txt"
  i=$((i+1))
done
# Le concat demuxer exige de répéter la dernière image (sinon sa durée est ignorée)
echo "file '$(printf "$TMP/frame_%02d.png" $((i-1)))'" >> "$TMP/list.txt"

echo "→ Génération de la palette…"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" \
  -vf "palettegen=stats_mode=diff" "$TMP/palette.png"

echo "→ Assemblage du GIF…"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" -i "$TMP/palette.png" \
  -lavfi "paletteuse=dither=bayer:bayer_scale=3" -loop 0 "$OUT"

SIZE=$(ls -lh "$OUT" | awk '{print $5}')
echo "✅ $OUT ($SIZE)"
