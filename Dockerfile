FROM node:20

# Základní nástroje
RUN apt-get update && apt-get install -y \
  git \
  openssh-client \
  curl \
  wget \
  jq \
  unzip \
  build-essential \
  python3 \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

# Go (latest stable)
RUN curl -fsSL https://go.dev/dl/go1.23.6.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
ENV GOPATH="/usr/local/gotools"
ENV PATH="${GOPATH}/bin:${PATH}"

# Běžné Go nástroje (instalace do sdíleného adresáře)
RUN mkdir -p "$GOPATH" && \
    go install golang.org/x/tools/gopls@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install golang.org/x/tools/cmd/goimports@latest && \
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
    chmod -R 755 "$GOPATH"

# Node.js globální nástroje
RUN npm i -g \
  typescript \
  ts-node \
  eslint \
  prettier \
  nodemon \
  pnpm

# Claude Code
RUN npm i -g @anthropic-ai/claude-code

WORKDIR /work
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
