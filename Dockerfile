FROM ruby:3.3

RUN gem install eth rlp sinatra rackup puma rack-contrib
WORKDIR /app

COPY eth_tool.rb .
COPY eth_tool_api.rb .

# ENV ETH_RPC_URL=http://geth:8545
ENV ETH_RPC_URL=https://dry-wispy-gas.quiknode.pro/

ENV KEYSTORE_DIR=/app/keystores

RUN mkdir -p /app/keystores

EXPOSE 3000
ENTRYPOINT ["ruby", "/app/eth_tool_api.rb"]