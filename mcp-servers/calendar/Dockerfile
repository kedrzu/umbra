# Calendar MCP Server
# Wraps @nspady/google-calendar-mcp with HTTP transport

FROM node:20-alpine

# Install git for cloning and wget for healthcheck
RUN apk add --no-cache git wget

# Create non-root user
RUN addgroup -S mcp && adduser -S mcp -G mcp

WORKDIR /app

# Clone and build the calendar MCP
RUN git clone --depth 1 https://github.com/nspady/google-calendar-mcp.git . && \
    npm ci && \
    npm run build && \
    rm -rf .git

# Create config directories
RUN mkdir -p /config/tokens && chown -R mcp:mcp /config /app

USER mcp

ENV NODE_ENV=production
ENV MCP_PORT=3003
ENV MODE=http
ENV GOOGLE_OAUTH_CREDENTIALS=/config/gcp-oauth.keys.json
ENV GOOGLE_TOKEN_PATH=/config/tokens

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:3003/health || exit 1

CMD ["node", "dist/index.js"]
