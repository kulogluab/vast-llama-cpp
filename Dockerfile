FROM vastai/base-image:cuda-12.1.1-auto

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    openssl \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir -U huggingface_hub hf_transfer

WORKDIR /opt

RUN git clone https://github.com/ggml-org/llama.cpp.git \
 && cd llama.cpp \
 && cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --config Release -j"$(nproc)"

COPY start-llama.sh /usr/local/bin/start-llama
RUN chmod +x /usr/local/bin/start-llama

WORKDIR /workspace

EXPOSE 18000

CMD ["/usr/local/bin/start-llama"]
