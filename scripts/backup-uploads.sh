#!/usr/bin/env bash
# Backup gambar upload produk.
#
# Gambar TIDAK di-commit ke git (repo publik + ukuran membengkak), jadi folder
# public/uploads/ hanya ada di server. Skrip ini yang menjaga supaya tidak hilang.
#
# Pakai:
#   bash scripts/backup-uploads.sh                 # simpan ke /tmp
#   bash scripts/backup-uploads.sh /path/tujuan    # simpan ke folder lain
#
# Saran: jalankan lewat cron harian.
#   ⚠️ PATH cron hanya /usr/bin:/bin — kalau nanti butuh tool di ~/.local/bin,
#      export PATH dulu di dalam crontab.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/public/uploads"
DEST_DIR="${1:-/tmp}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT="$DEST_DIR/atara_uploads_${STAMP}.tar.gz"

if [ ! -d "$SRC" ]; then
  echo "Tidak ada folder upload: $SRC" >&2
  exit 1
fi

COUNT="$(find "$SRC" -maxdepth 1 -type f | wc -l | tr -d ' ')"
SIZE="$(du -sh "$SRC" | cut -f1)"

tar -czf "$OUT" -C "$REPO_DIR/public" uploads
echo "Backup: $OUT"
echo "File: $COUNT · Ukuran: $SIZE"

# Simpan 7 backup terbaru, hapus sisanya supaya disk tidak penuh.
ls -1t "$DEST_DIR"/atara_uploads_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
echo "Backup tersimpan: $(ls -1 "$DEST_DIR"/atara_uploads_*.tar.gz 2>/dev/null | wc -l | tr -d ' ') (maks 7)"
