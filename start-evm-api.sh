# Scripts for managing the multi-chain setup

# Start all blockchain proxies
docker-compose up -d ethereum-rpc polygon-rpc bsc-rpc arbitrum-rpc

# Check status
docker-compose ps

# View logs for specific chain
docker-compose logs -f ethereum-rpc

# Scale specific chain (if needed)  
docker-compose up -d --scale polygon-rpc=2 polygon-rpc

