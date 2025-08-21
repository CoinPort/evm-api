FROM ruby:3.3

# Install required gems including yaml (psych is built-in for YAML support)
RUN gem install eth rlp sinatra rackup puma rack-contrib
WORKDIR /app

COPY eth_tool.rb .
COPY eth_tool_api.rb .

# Set default environment variables
ENV ETH_RPC_URL=https://dry-wispy-gas.quiknode.pro/
ENV KEYSTORE_DIR=/opt/wallets
ENV PORT=3000
ENV RACK_ENV=production

# Create keystore directory with proper permissions
RUN mkdir -p /opt/wallets && chmod 700 /opt/wallets

# Create non-root user for security
# Alpine
# RUN addgroup -g 1000 app && \
#    adduser -u 1000 -G app -s /bin/sh -D app && \
#    chown -R appuser:app /app /opt/wallets

RUN groupadd -g 1000 app && \
    useradd -u 1000 -g app -m app && \
    chown -R app:app /app /opt/wallets

# Switch to non-root user
USER app

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["ruby", "/app/eth_tool_api.rb"]
