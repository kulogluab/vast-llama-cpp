FROM vastai/base-image:cuda-12.1.1-auto

SHELL ["/bin/bash", "-lc"]

WORKDIR /opt/workspace-internal

RUN . /venv/main/bin/activate && \
    uv pip install --no-cache-dir huggingface_hub hf_transfer

WORKDIR /opt

RUN git clone https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && \
    cmake -B build \
      -DGGML_CUDA=ON \
      -DLLAMA_CURL=ON \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release -j"$(nproc)"

COPY start-llama.sh /usr/local/bin/start-llama
RUN chmod +x /usr/local/bin/start-llama

WORKDIR /workspace

EXPOSE 18000

CMD ["/usr/local/bin/start-llama"]
