# Standard Ruby image (larger but more reliable)
FROM ruby:3.3

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Ruby gems
RUN gem install --no-document \
    eth \
    rlp \
    sinatra \
    rackup \
    puma \
    rack-contrib

WORKDIR /app

# Copy application files
COPY eth_tool.rb eth_tool_api.rb ./

# Set default environment variables
ENV ETH_RPC_URL=https://dry-wispy-gas.quiknode.pro/
ENV KEYSTORE_DIR=/opt/wallets
ENV PORT=3000
ENV RACK_ENV=production

# Create keystore directory
RUN mkdir -p /opt/wallets && chmod 700 /opt/wallets

# Create non-root user
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -m appuser && \
    chown -R appuser:appuser /app /opt/wallets

USER appuser

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["ruby", "/app/eth_tool_api.rb"]
