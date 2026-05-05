FROM vastai/base-image:cuda-12.1.1-auto

SHELL ["/bin/bash", "-lc"]

ARG LLAMA_CPP_REF=master

# Keep this list small. Add/remove architectures based on the GPUs you rent.
# 75 = T4
# 80 = A100
# 86 = RTX 3090 / A6000 / A40
# 89 = RTX 4090 / L4 / L40 / L40S
# 90 = H100 / H200
# 120 = Blackwell, requires CUDA 12.8+
ARG CUDA_ARCHITECTURES="86;89"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    ninja-build \
    build-essential \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    openssl \
 && rm -rf /var/lib/apt/lists/*

RUN if [[ -f /venv/main/bin/activate ]]; then source /venv/main/bin/activate; fi && \
    python3 -m pip install --no-cache-dir -U huggingface_hub hf_transfer

WORKDIR /opt

RUN git clone --depth 1 --branch "$LLAMA_CPP_REF" https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && \
    cmake -B build -G Ninja \
      -DGGML_CUDA=ON \
      -DLLAMA_CURL=ON \
      -DGGML_NATIVE=OFF \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --target llama-server -j 2 && \
    strip build/bin/llama-server || true && \
    rm -rf .git build/examples build/tests build/tools

COPY start-llama.sh /usr/local/bin/start-llama
RUN chmod +x /usr/local/bin/start-llama

WORKDIR /workspace

EXPOSE 18000

CMD ["/usr/local/bin/start-llama"]
