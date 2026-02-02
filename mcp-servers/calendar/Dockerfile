# Calendar MCP Server
# Wraps @nspady/google-calendar-mcp with HTTP transport

FROM node:20-alpine

# Install git for cloning
RUN apk add --no-cache git

WORKDIR /app

# Clone and build the calendar MCP
RUN git clone --depth 1 https://github.com/nspady/google-calendar-mcp.git . && \
    npm ci && \
    npm run build && \
    rm -rf .git

# Create non-root user and config directories
RUN addgroup -S mcp && adduser -S mcp -G mcp && \
    mkdir -p /config/tokens && chown -R mcp:mcp /config /app

USER mcp

ENV NODE_ENV=production
ENV TRANSPORT=http
ENV HOST=0.0.0.0
ENV PORT=4003
ENV GOOGLE_OAUTH_CREDENTIALS=/config/gcp-oauth.keys.json
ENV GOOGLE_CALENDAR_MCP_TOKEN_PATH=/config/tokens/tokens.json

EXPOSE 4003

CMD ["node", "build/index.js"]
