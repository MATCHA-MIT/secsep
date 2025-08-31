# syntax=docker/dockerfile:1

FROM ubuntu:22.04


USER root
ENV HOME=/root
ENV SECSEP_ROOT=/root/secsep
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8


# Install dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    rm -rf /var/cache/apt/archives/lock && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnupg gnupg2 wget ca-certificates apt-transport-https \
        autoconf automake cmake dpkg-dev file make patch pkg-config \
        lsb-release software-properties-common \
        build-essential cmake ninja-build m4 scons \
        libc6-dev libtinfo-dev libzstd-dev zlib1g zlib1g-dev libxml2-dev libedit-dev libgmp-dev \
        libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
        doxygen libboost-all-dev libhdf5-serial-dev libpng-dev libelf-dev \
        git curl zsh vim tmux gdb black \
        pipx opam golang-go


# Install and use oh-my-zsh
RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh > install.sh && \
    sh install.sh && \
    rm install.sh
ENV THEME="ys"
RUN sed -i 's/^ZSH_THEME=".\+"$/ZSH_THEME="$THEME"/g' ~/.zshrc
SHELL ["/bin/zsh", "-c"]
RUN chsh -s /bin/zsh


# Install Poetry
WORKDIR $SECSEP_ROOT
RUN --mount=type=cache,target=$HOME/.cache \
    pipx install poetry && \
    pipx install virtualenv
ENV PATH="$HOME/.local/bin:$PATH"
ENV VIRTUAL_ENV=$HOME/.venv
RUN virtualenv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
# COPY pyproject.toml poetry.lock $SECSEP_ROOT
COPY pyproject.toml $SECSEP_ROOT
RUN --mount=type=cache,target=$HOME/.cache \
    poetry install


# Build LLVM 16.0.6
WORKDIR $HOME
RUN git clone --branch llvmorg-16.0.6 --depth 1 https://github.com/llvm/llvm-project.git
RUN mkdir -p $HOME/llvm-project/build
WORKDIR $HOME/llvm-project/build
RUN cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local/llvm-16 \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=ON \
  -DLLVM_LINK_LLVM_DYLIB=ON \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,--no-keep-memory" \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--no-keep-memory" \
  ../llvm
RUN bash -euxo pipefail -c '\
  J=$(nproc); MINJ=4; ATTEMPTS=0; MAX_ATTEMPTS=6; \
  echo "Starting ninja with -j${J} (will back off on failure, min ${MINJ})"; \
  until ninja -j"${J}"; do \
    ATTEMPTS=$((ATTEMPTS+1)); \
    if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then \
      echo "Build still fails after ${ATTEMPTS} attempts"; exit 1; \
    fi; \
    echo "ninja failed (likely OOM). Backing off parallelism..."; \
    J=$(( (J+1)/2 )); \
    if [ "${J}" -lt "${MINJ}" ]; then J=${MINJ}; fi; \
    echo "Retrying with -j${J} (attempt ${ATTEMPTS}/${MAX_ATTEMPTS})"; \
  done; \
  ninja install \
'
RUN ln -sf /usr/local/llvm-16/bin/clang        /usr/local/bin/clang-16        && \
    ln -sf /usr/local/llvm-16/bin/llc          /usr/local/bin/llc-16          && \
    ln -sf /usr/local/llvm-16/bin/opt          /usr/local/bin/opt-16          && \
    ln -sf /usr/local/llvm-16/bin/llvm-readobj /usr/local/bin/llvm-readobj-16 && \
    ln -sf /usr/local/llvm-16/bin/llvm-config  /usr/local/bin/llvm-config-16

RUN rm -rf $HOME/llvm-project


# Install ocaml and required packages
# Keep it at the end since it unfolds and sets the PATH variable in .*rc file
RUN opam init -y && \
    opam switch create scale 4.14.2 && \
    opam switch create octal 5.3.0 && \
    opam install -y --switch=scale stdcompat.19 refl dune core core_unix sexp && \
    opam install -y --switch=octal dune core z3 sexp && \
    echo "eval $(opam env --switch=octal --set-switch)" >> ~/.zshrc

# Build and install clangml for clang 16.0.6
RUN git clone https://github.com/ocamllibs/clangml.git $HOME/clangml
WORKDIR $HOME/clangml
RUN git checkout 52df9b7
# Need to fix curl redirect bug in m4/download.sh
RUN ulimit -s unlimited && eval $(opam env --switch=scale) && \
    sed -i 's/curl\s*"\$url"/curl -L "\$url"/' m4/download.sh && \
    ./bootstrap.sh && \
    ./configure --with-llvm-config=/usr/local/bin/llvm-config-16 && \
    make && make install


RUN git config --global --add safe.directory /root/secsep/gem5
WORKDIR $SECSEP_ROOT
CMD ["/bin/zsh"]
