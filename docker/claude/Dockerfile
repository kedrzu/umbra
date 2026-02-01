# Claude Code Container with qmd
# Provides sandboxed Claude Code with MCP access only

FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    ripgrep \
    curl \
    wget \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install bun for qmd
RUN curl -fsSL https://bun.sh/install | bash
ENV BUN_INSTALL="/root/.bun"
ENV PATH="$BUN_INSTALL/bin:$PATH"

# Install qmd
RUN bun install -g qmd

# Create non-root user
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.cache/qmd && \
    mkdir -p /home/claude/.claude && \
    mkdir -p /home/claude/.bun && \
    chown -R claude:claude /home/claude

# Copy bun installation to claude user
RUN cp -r /root/.bun/* /home/claude/.bun/

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Set up environment
ENV PATH="/home/claude/.bun/bin:$PATH"
ENV HOME=/home/claude
ENV XDG_CACHE_HOME=/home/claude/.cache

# Switch to non-root user
USER claude
WORKDIR /workspace

# Default command - interactive Claude Code session
ENTRYPOINT ["claude"]
CMD ["--help"]
