# Use Alpine for smaller base image
FROM ruby:3.3-alpine

# Install build dependencies and runtime dependencies in one layer
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    git \
    openssl-dev \
    libffi-dev \
    && apk add --no-cache \
    curl \
    tzdata \
    openssl \
    libffi \
    && gem install --no-document \
    eth \
    rlp \
    sinatra \
    rackup \
    puma \
    rack-contrib \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/* \
    && rm -rf /root/.gem

WORKDIR /app

# Copy application files
COPY eth_tool.rb eth_tool_api.rb ./

# Set default environment variables
ENV ETH_RPC_URL=https://dry-wispy-gas.quiknode.pro/
ENV KEYSTORE_DIR=/opt/wallets
ENV PORT=3000
ENV RACK_ENV=production

# Create keystore directory with proper permissions
RUN mkdir -p /opt/wallets && chmod 700 /opt/wallets

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -u 1000 -G appuser -s /bin/sh -D appuser && \
    chown -R appuser:appuser /app /opt/wallets

# Switch to non-root user
USER appuser

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["ruby", "/app/eth_tool_api.rb"]