#!/bin/bash

echo "================================================"
echo "  PeakMiner · Startup Check"
echo "================================================"

# Check NVIDIA driver
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d'.' -f1)

if [ -z "$DRIVER_VERSION" ]; then
    echo "⚠️  WARNING: NVIDIA driver tidak terdeteksi!"
    echo "   GPU mining tidak akan berjalan."
else
    echo "✅ NVIDIA Driver v${DRIVER_VERSION} — terdeteksi"
fi

# Validate required ENVs
MISSING=0
if [ -z "$COIN" ]; then
    echo "❌ COIN belum diisi! (contoh: quantus, pearl, btx)"
    MISSING=1
fi
if [ -z "$POOL" ]; then
    echo "❌ POOL belum diisi!"
    MISSING=1
fi
if [ -z "$WALLET" ]; then
    echo "❌ WALLET belum diisi!"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo "Isi semua ENV yang wajib lalu restart container."
    exit 1
fi

# Gabungkan wallet + worker jadi satu string "wallet.worker"
# karena PeakMiner pakai format ini di flag -u, bukan flag --worker terpisah
if [ -n "$WORKER" ]; then
    FULL_WALLET="${WALLET}.${WORKER}"
else
    FULL_WALLET="$WALLET"
fi

echo ""
echo "  COIN       : $COIN"
echo "  POOL       : $POOL"
echo "  WORKER     : $WORKER"
echo "  WALLET     : $FULL_WALLET"
echo "  EXTRA_ARGS : ${EXTRA_ARGS:-<none>}"
echo "================================================"
echo ""

# ── Loop: jalankan miner, auto-restart kalau crash ──
# $EXTRA_ARGS sengaja tanpa kutip supaya terpecah jadi beberapa argumen
while true; do
    /usr/local/bin/peakminer \
        --coin "$COIN" \
        -o "$POOL" \
        -u "$FULL_WALLET" \
        $EXTRA_ARGS 2>&1

    EXIT_CODE=$?
    echo ""
    echo "❌ PeakMiner berhenti dengan exit code: $EXIT_CODE"
    echo "🔁 Restart miner dalam 5 detik..."
    sleep 5
done
