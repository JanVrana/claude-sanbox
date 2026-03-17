FROM node:20

# GitHub CLI repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list

# Base tools + CLI utilities for Claude Code
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
  gosu \
  rsync \
  gh \
  ripgrep \
  fd-find \
  tree \
  less \
  zip \
  sqlite3 \
  && rm -rf /var/lib/apt/lists/*

# fdfind → fd symlink (Debian package is named fd-find)
RUN ln -s $(which fdfind) /usr/local/bin/fd

# Delta — beautiful git diff viewer (side-by-side diffs)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" \
      -o /tmp/delta.deb && \
    dpkg -i /tmp/delta.deb && rm /tmp/delta.deb

# Go (latest stable)
RUN curl -fsSL https://go.dev/dl/go1.23.6.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
ENV GOPATH="/usr/local/gotools"
ENV PATH="${GOPATH}/bin:${PATH}"

# Common Go tools (installed to shared directory)
RUN mkdir -p "$GOPATH" && \
    go install golang.org/x/tools/gopls@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install golang.org/x/tools/cmd/goimports@latest && \
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
    chmod -R 755 "$GOPATH"

# Node.js global tools
RUN npm i -g \
  typescript \
  ts-node \
  eslint \
  prettier \
  nodemon \
  pnpm

# Claude Code
RUN npm i -g @anthropic-ai/claude-code

COPY commands/ /etc/claude-commands/
COPY default-settings.json /etc/claude-defaults/settings.json

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
