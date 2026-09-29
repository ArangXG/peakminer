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

# ── Kumpulkan semua pool jadi array ──
# Cara isi (boleh dicampur):
#   1) POOL   = satu atau banyak pool, dipisah koma (,) atau titik koma (;)
#   2) POOL2..POOL8 = pool tambahan, satu variabel satu pool
#      (berguna untuk platform seperti Salad yang memecah nilai berkoma di form ENV)
# Contoh:
#   POOL="stratum+tcp://qtc.kryptex.network:7049"
#   POOL2="stratum+tcp://qtc-sg.kryptex.network:7049"
#   POOL3="stratum+tcp://qtc-eu.kryptex.network:7049"
ALL_POOL="$POOL"
for n in 2 3 4 5 6 7 8; do
    v="POOL$n"
    [ -n "${!v}" ] && ALL_POOL="${ALL_POOL},${!v}"
done
ALL_POOL="${ALL_POOL//;/,}"

POOLS=()
IFS=',' read -ra _RAW_POOLS <<< "$ALL_POOL"
for p in "${_RAW_POOLS[@]}"; do
    p="${p// /}"
    [ -n "$p" ] && POOLS+=("$p")
done
POOL_COUNT=${#POOLS[@]}

if [ "$POOL_COUNT" -eq 0 ]; then
    echo "❌ POOL tidak berisi alamat yang valid!"
    exit 1
fi

# ── Pengaturan ganti pool otomatis (semua opsional) ──
# MAX_FAILS   : gagal konek berapa kali berturut-turut sebelum ganti pool (0 = matikan, serahkan ke failover bawaan PeakMiner)
# RESET_AFTER : kalau jeda antar error lebih dari N detik, hitungan gagal dianggap mulai dari nol
# MAX_ROUNDS  : setelah semua pool dicoba sebanyak N putaran dan tetap gagal, container keluar (exit 1) agar platform bisa restart. 0 = tidak pernah keluar
[[ "$MAX_FAILS"   =~ ^[0-9]+$ ]] || MAX_FAILS=3
[[ "$RESET_AFTER" =~ ^[0-9]+$ ]] || RESET_AFTER=180
[[ "$MAX_ROUNDS"  =~ ^[0-9]+$ ]] || MAX_ROUNDS=0

echo ""
echo "  COIN        : $COIN"
echo "  WORKER      : $WORKER"
echo "  WALLET      : $FULL_WALLET"
echo "  EXTRA_ARGS  : ${EXTRA_ARGS:-<none>}"
echo "  MAX_FAILS   : $MAX_FAILS   RESET_AFTER: ${RESET_AFTER}s   MAX_ROUNDS: $MAX_ROUNDS"
echo "  POOL ($POOL_COUNT):"
for i in "${!POOLS[@]}"; do
    echo "    $((i+1)). ${POOLS[$i]}"
done
echo "================================================"
echo ""

# Baris error koneksi dari PeakMiner (dipakai untuk menghitung gagal konek)
FAIL_RE='ERROR.*([Tt]imed out|[Cc]onnect|[Rr]efused|[Uu]nreachable|[Rr]esolve)'

FIFO="$(mktemp -u /tmp/peak.XXXXXX)"
mkfifo "$FIFO"
MINER_PID=""
trap 'kill "$MINER_PID" 2>/dev/null; rm -f "$FIFO"; exit 0' TERM INT

IDX=0
ROUNDS=0

# ── Loop: jalankan miner, ganti pool kalau gagal konek, auto-restart kalau crash ──
while true; do
    # Urutan pool: mulai dari pool aktif, sisanya menyusul.
    # Jadi failover bawaan PeakMiner tetap jalan sebagai cadangan.
    POOL_ARGS=()
    for ((i = 0; i < POOL_COUNT; i++)); do
        POOL_ARGS+=(-o "${POOLS[$(( (IDX + i) % POOL_COUNT ))]}")
    done
    echo "🌐 Pool aktif: ${POOLS[$IDX]}  ($((IDX + 1))/$POOL_COUNT)"

    START=$(date +%s)
    /usr/local/bin/peakminer \
        --coin "$COIN" \
        "${POOL_ARGS[@]}" \
        -u "$FULL_WALLET" \
        --no-color \
        $EXTRA_ARGS > "$FIFO" 2>&1 &
    MINER_PID=$!

    FAILS=0
    LAST_FAIL=0
    ROTATE=0
    while IFS= read -r line; do
        echo "$line"
        if [ "$MAX_FAILS" -gt 0 ] && [[ "$line" =~ $FAIL_RE ]]; then
            NOW=$(date +%s)
            if [ $((NOW - LAST_FAIL)) -gt "$RESET_AFTER" ]; then
                FAILS=0
            fi
            FAILS=$((FAILS + 1))
            LAST_FAIL=$NOW
            if [ "$FAILS" -ge "$MAX_FAILS" ]; then
                ROTATE=1
                break
            fi
        fi
    done < "$FIFO"

    if [ "$ROTATE" -eq 1 ]; then
        kill "$MINER_PID" 2>/dev/null
        wait "$MINER_PID" 2>/dev/null
        echo ""
        echo "🔀 Gagal konek ${MAX_FAILS}x berturut-turut ke ${POOLS[$IDX]} — ganti pool"

        # Kalau sesi tadi sempat jalan lama (>10 menit), anggap pool pernah sehat: hitungan putaran diulang
        if [ $(( $(date +%s) - START )) -gt 600 ]; then
            ROUNDS=0
        fi

        IDX=$(( (IDX + 1) % POOL_COUNT ))
        if [ "$IDX" -eq 0 ]; then
            ROUNDS=$((ROUNDS + 1))
            echo "🔄 Semua pool sudah dicoba (putaran ke-${ROUNDS})"
            if [ "$MAX_ROUNDS" -gt 0 ] && [ "$ROUNDS" -ge "$MAX_ROUNDS" ]; then
                echo "❌ Semua pool gagal ${ROUNDS} putaran — container keluar (exit 1)"
                rm -f "$FIFO"
                exit 1
            fi
        fi
        sleep 2
    else
        wait "$MINER_PID"
        EXIT_CODE=$?
        echo ""
        echo "❌ PeakMiner berhenti dengan exit code: $EXIT_CODE"
        echo "🔁 Restart miner dalam 5 detik..."
        sleep 5
    fi
done
