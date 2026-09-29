#!/bin/bash

echo "================================================"
echo "  PeakMiner · Quantus Startup Check"
echo "================================================"

# Check NVIDIA driver
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d'.' -f1)

if [ -z "$DRIVER_VERSION" ]; then
    echo "⚠️  WARNING: NVIDIA driver tidak terdeteksi!"
    echo "   GPU mining tidak akan berjalan."
else
    echo "✅ NVIDIA Driver v${DRIVER_VERSION} — terdeteksi"
    echo "   GPU siap dipakai untuk quantus."
fi

# Validate required ENVs
MISSING=0
if [ -z "$QTC_WALLET" ]; then
    echo "❌ QTC_WALLET belum diisi!"
    MISSING=1
fi
if [ -z "$QTC_POOL" ]; then
    echo "❌ QTC_POOL belum diisi!"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo "Isi semua ENV yang wajib lalu restart container."
    exit 1
fi

# Gabungkan wallet + worker jadi satu string "wallet.worker"
# karena PeakMiner pakai format ini di flag -u, bukan flag --worker terpisah
if [ -n "$QTC_WORKER" ]; then
    FULL_WALLET="${QTC_WALLET}.${QTC_WORKER}"
else
    FULL_WALLET="$QTC_WALLET"
fi

echo ""
echo "  QTC_POOL   : $QTC_POOL"
echo "  QTC_WORKER : $QTC_WORKER"
echo "  WALLET     : $FULL_WALLET"
echo "================================================"
echo ""

# ── Loop: jalankan miner, auto-restart kalau crash ──
while true; do
    /usr/local/bin/peakminer \
        --coin quantus \
        -o "$QTC_POOL" \
        -u "$FULL_WALLET" 2>&1

    EXIT_CODE=$?
    echo ""
    echo "❌ PeakMiner berhenti dengan exit code: $EXIT_CODE"
    echo "🔁 Restart miner dalam 5 detik..."
    sleep 5
done
