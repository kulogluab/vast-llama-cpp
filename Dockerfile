FROM vastai/base-image:cuda-12.1.1-auto

SHELL ["/bin/bash", "-lc"]

ARG LLAMA_CPP_REF=master

# 86 = RTX 3090 / RTX A6000
# 89 = RTX 4090 / L40 / L40S
ARG CUDA_ARCHITECTURES="86;89"

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    printf '%s\n' \
      'Acquire::Retries "10";' \
      'Acquire::http::Timeout "120";' \
      'Acquire::https::Timeout "120";' \
      'Acquire::ftp::Timeout "120";' \
      'Acquire::Queue-Mode "host";' \
      > /etc/apt/apt.conf.d/99-retries; \
    for attempt in 1 2 3 4 5; do \
      echo "APT install attempt ${attempt}/5"; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
      if apt-get update && apt-get install -y --no-install-recommends --fix-missing \
        git \
        cmake \
        ninja-build \
        build-essential \
        curl \
        ca-certificates \
        python3 \
        python3-pip \
        openssl; then \
        break; \
      fi; \
      if [[ "$attempt" == "5" ]]; then \
        echo "APT install failed after ${attempt} attempts"; \
        exit 1; \
      fi; \
      sleep $((attempt * 20)); \
    done; \
    rm -rf /var/lib/apt/lists/*

RUN if [[ -f /venv/main/bin/activate ]]; then source /venv/main/bin/activate; fi && \
    python3 -m pip install --no-cache-dir -U huggingface_hub hf_transfer

WORKDIR /opt

RUN set -eux; \
    git clone --depth 1 --branch "$LLAMA_CPP_REF" https://github.com/ggml-org/llama.cpp.git; \
    cd llama.cpp; \
    cmake -B build -G Ninja \
      -DGGML_CUDA=ON \
      -DLLAMA_CURL=ON \
      -DGGML_NATIVE=OFF \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
      -DCMAKE_BUILD_TYPE=Release; \
    cmake --build build --target llama-server -j 2; \
    echo "Searching for built llama-server binary..."; \
    LLAMA_SERVER_BIN="$(find /opt/llama.cpp/build -type f -name llama-server -perm -111 | head -n 1)"; \
    if [[ -z "$LLAMA_SERVER_BIN" ]]; then \
      echo "ERROR: llama-server binary was not found after build"; \
      find /opt/llama.cpp/build -maxdepth 5 -type f | sort | tail -200; \
      exit 1; \
    fi; \
    echo "Found llama-server at: $LLAMA_SERVER_BIN"; \
    mkdir -p /usr/local/lib/llama.cpp; \
    ln -sf "$LLAMA_SERVER_BIN" /usr/local/lib/llama.cpp/llama-server-real; \
    test -x /usr/local/lib/llama.cpp/llama-server-real; \
    strip "$LLAMA_SERVER_BIN" || true; \
    rm -rf /opt/llama.cpp/.git

COPY llama-server-wrapper /usr/local/bin/llama-server
COPY start-llama.sh /usr/local/bin/start-llama

RUN chmod +x /usr/local/bin/llama-server /usr/local/bin/start-llama

WORKDIR /workspace

EXPOSE 18000

CMD ["/usr/local/bin/start-llama"]
