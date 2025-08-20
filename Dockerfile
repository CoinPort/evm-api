FROM ruby:3.3

# Install required gems including yaml (psych is built-in for YAML support)
RUN gem install eth rlp sinatra rackup puma rack-contrib
WORKDIR /app

COPY eth_tool.rb .
COPY eth_tool_api.rb .

# Set default environment variables
ENV ETH_RPC_URL=https://dry-wispy-gas.quiknode.pro/
ENV KEYSTORE_DIR=/app/keystores

# Create keystore directory (now using /opt/wallets for Docker volume mounting)
RUN mkdir -p /app/keystores

EXPOSE 3000

ENTRYPOINT ["ruby", "/app/eth_tool_api.rb"]