FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    libstdc++6 \
    libgomp1 \
    ca-certificates \
    libnuma1 \
    libhwloc15 \
    ocl-icd-libopencl1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Download PeakMiner versi spesifik (di-passing dari workflow lewat build-arg),
# bukan "latest" yang di-resolve ulang tiap build — jadi image selalu pasti
# dapat versi yang sudah dicek dan dicatat oleh workflow.
# Asset yang diambil: peakminer-<versi>-linux-x86_64 (binary standalone, bukan .tar.gz)
ARG PEAK_VERSION
RUN test -n "$PEAK_VERSION" \
    && PEAK_URL=$(wget -qO- "https://api.github.com/repos/peakminer/peakminer/releases/tags/${PEAK_VERSION}" \
        | grep -oE '"browser_download_url": *"[^"]*-linux-x86_64"' \
        | grep -oE 'https://[^"]+' \
        | head -n1) \
    && test -n "$PEAK_URL" \
    && echo ">>> PeakMiner ${PEAK_VERSION}: $PEAK_URL" \
    && wget -q "$PEAK_URL" -O /usr/local/bin/peakminer \
    && chmod +x /usr/local/bin/peakminer

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── GPU Mining · PeakMiner · NVIDIA ──────────────────────────
# Semua diisi lewat "docker run -e ..." (tidak ada yang hard code)
ENV COIN=
ENV POOL=
ENV WALLET=
ENV WORKER=
# Opsional: flag tambahan untuk peakminer, contoh: "--no-color"
ENV EXTRA_ARGS=

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
