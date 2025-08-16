Great! Here's how to implement multi-chain EVM support in your Peatio setup using shared wallet files:

## 1. **Multi-Chain Wallet Service**

Create a comprehensive wallet service that handles multiple EVM chains:

```ruby
# lib/multi_chain_ethereum_wallet.rb
class MultiChainEthereumWallet
  SUPPORTED_CHAINS = {
    ethereum: {
      quicknode_url: Rails.application.credentials.ethereum[:quicknode_url],
      chain_id: 1,
      currency_code: 'eth',
      gas_limit: 21000,
      min_gas_price: 1_000_000_000 # 1 Gwei
    },
    polygon: {
      quicknode_url: Rails.application.credentials.polygon[:quicknode_url],
      chain_id: 137,
      currency_code: 'matic',
      gas_limit: 21000,
      min_gas_price: 30_000_000_000 # 30 Gwei
    },
    bsc: {
      quicknode_url: Rails.application.credentials.bsc[:quicknode_url],
      chain_id: 56,
      currency_code: 'bnb',
      gas_limit: 21000,
      min_gas_price: 5_000_000_000 # 5 Gwei
    },
    arbitrum: {
      quicknode_url: Rails.application.credentials.arbitrum[:quicknode_url],
      chain_id: 42161,
      currency_code: 'arb',
      gas_limit: 21000,
      min_gas_price: 100_000_000 # 0.1 Gwei
    }
  }.freeze

  def initialize(wallet_dir: '/opt/peatio/wallets')
    @wallet_dir = wallet_dir
    ensure_wallet_directory
  end

  # Creates address that works across ALL EVM chains
  def create_universal_address(password)
    key = Eth::Key.new
    address = key.address.downcase
    
    # Create encrypted keystore (Geth-compatible format)
    keystore = create_encrypted_keystore(key.private_hex, password)
    
    # Save wallet file (one file works for all chains)
    wallet_file = File.join(@wallet_dir, "#{address}.json")
    File.write(wallet_file, JSON.pretty_generate(keystore))
    File.chmod(0600, wallet_file)
    
    {
      address: address,
      supported_chains: SUPPORTED_CHAINS.keys
    }
  end

  # Send transaction on specified chain
  def send_transaction(chain:, from:, to:, value:, password:, gas_price: nil)
    raise "Unsupported chain: #{chain}" unless SUPPORTED_CHAINS.key?(chain.to_sym)
    
    chain_config = SUPPORTED_CHAINS[chain.to_sym]
    
    # Load private key from local wallet file
    private_key = load_private_key(from, password)
    key = Eth::Key.new(priv: private_key)
    
    # Get transaction parameters from appropriate QuickNode endpoint
    nonce = get_nonce(from, chain_config[:quicknode_url])
    gas_price ||= get_gas_price(chain_config[:quicknode_url])
    gas_price = [gas_price, chain_config[:min_gas_price]].max
    
    # Create transaction with chain-specific parameters
    tx = Eth::Tx.new({
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: chain_config[:gas_limit],
      to: to,
      value: value,
      chain_id: chain_config[:chain_id]  # Important for EIP-155
    })
    
    tx.sign(key)
    
    # Broadcast to appropriate chain
    txid = send_raw_transaction(tx.hex, chain_config[:quicknode_url])
    
    {
      txid: txid,
      chain: chain,
      from: from,
      to: to,
      value: value
    }
  end

  # Get balance on specific chain
  def get_balance(address, chain)
    chain_config = SUPPORTED_CHAINS[chain.to_sym]
    balance_wei = quicknode_rpc('eth_getBalance', [address, 'latest'], chain_config[:quicknode_url])
    balance_wei.to_i(16)
  end

  private

  def load_private_key(address, password)
    wallet_file = File.join(@wallet_dir, "#{address.downcase}.json")
    raise "Wallet file not found for #{address}" unless File.exist?(wallet_file)
    
    keystore = JSON.parse(File.read(wallet_file))
    decrypt_keystore(keystore, password)
  end

  def create_encrypted_keystore(private_key, password)
    # Use eth gem's encryption (Geth-compatible)
    Eth::Key.encrypt(private_key, password)
  end

  def decrypt_keystore(keystore, password)
    Eth::Key.decrypt(keystore, password)
  end

  def quicknode_rpc(method, params, quicknode_url)
    uri = URI(quicknode_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: SecureRandom.uuid
    }.to_json
    
    response = http.request(request)
    result = JSON.parse(response.body)
    
    raise "RPC Error: #{result['error']}" if result['error']
    result['result']
  end

  def get_nonce(address, quicknode_url)
    quicknode_rpc('eth_getTransactionCount', [address, 'pending'], quicknode_url).to_i(16)
  end

  def get_gas_price(quicknode_url)
    quicknode_rpc('eth_gasPrice', [], quicknode_url).to_i(16)
  end

  def send_raw_transaction(signed_hex, quicknode_url)
    quicknode_rpc('eth_sendRawTransaction', [signed_hex], quicknode_url)
  end

  def ensure_wallet_directory
    FileUtils.mkdir_p(@wallet_dir) unless Dir.exist?(@wallet_dir)
    File.chmod(0700, @wallet_dir)
  end
end
```

## 2. **Multi-Chain Peatio Currency Implementations**

Create separate currency classes that share the same wallet service:

```ruby
# app/models/wallets/ethereum.rb
module Wallets
  class Ethereum < Base
    def initialize(*)
      super
      @wallet_service = MultiChainEthereumWallet.new
      @chain = :ethereum
    end

    def create_address!(options = {})
      create_evm_address!(options, @chain)
    end

    def create_withdrawal!(transaction, options = {})
      create_evm_withdrawal!(transaction, @chain, options)
    end

    private

    def create_evm_address!(options, chain)
      password = generate_secure_password
      encrypted_password = vault_encrypt(password)
      
      result = @wallet_service.create_universal_address(password)
      
      PaymentAddress.create!(
        member: options[:member],
        wallet: self,
        address: result[:address],
        secret: encrypted_password,
        details: { supported_chains: result[:supported_chains] }
      )
      
      result[:address]
    end

    def create_evm_withdrawal!(transaction, chain, options)
      payment_address = PaymentAddress.find_by(address: transaction.from_address)
      password = vault_decrypt(payment_address.secret)
      
      result = @wallet_service.send_transaction(
        chain: chain,
        from: transaction.from_address,
        to: transaction.to_address,
        value: convert_to_wei(transaction.amount),
        password: password
      )
      
      transaction.update!(
        txid: result[:txid],
        block_number: nil, # Will be updated by deposit scanner
        details: { chain: chain }
      )
    end
  end
end

# app/models/wallets/polygon.rb  
module Wallets
  class Polygon < Ethereum
    def initialize(*)
      super
      @chain = :polygon
    end
  end
end

# app/models/wallets/bsc.rb
module Wallets
  class Bsc < Ethereum
    def initialize(*)
      super
      @chain = :bsc  
    end
  end
end

# app/models/wallets/arbitrum.rb
module Wallets
  class Arbitrum < Ethereum
    def initialize(*)
      super
      @chain = :arbitrum
    end
  end
end
```

## 3. **Currency Configuration**

Define each supported chain in your currencies configuration:

```yaml
# config/currencies.yml
currencies:
  eth:
    name: "Ethereum"
    symbol: "ETH"
    type: "coin"
    precision: 18
    wallet:
      adapter: "ethereum"
      hot_wallet_address: "0x..."
    
  matic:
    name: "Polygon"
    symbol: "MATIC" 
    type: "coin"
    precision: 18
    wallet:
      adapter: "polygon"
      hot_wallet_address: "0x..."
      
  bnb:
    name: "BNB Smart Chain"
    symbol: "BNB"
    type: "coin" 
    precision: 18
    wallet:
      adapter: "bsc"
      hot_wallet_address: "0x..."
      
  arb:
    name: "Arbitrum"
    symbol: "ARB"
    type: "coin"
    precision: 18
    wallet:
      adapter: "arbitrum" 
      hot_wallet_address: "0x..."
```

## 4. **Multi-Chain Deposit Scanner**

Extend your existing QuickNode deposit scanner for multiple chains:

```ruby
# lib/multi_chain_deposit_scanner.rb
class MultiChainDepositScanner
  def initialize
    @wallet_service = MultiChainEthereumWallet.new
    @chains = MultiChainEthereumWallet::SUPPORTED_CHAINS
  end

  def scan_all_chains
    @chains.each do |chain_name, config|
      scan_chain_deposits(chain_name, config)
    end
  end

  private

  def scan_chain_deposits(chain_name, chain_config)
    # Get latest block from QuickNode
    latest_block = get_latest_block(chain_config[:quicknode_url])
    last_scanned = get_last_scanned_block(chain_name)
    
    (last_scanned + 1..latest_block).each do |block_number|
      process_block_deposits(block_number, chain_name, chain_config)
    end
    
    update_last_scanned_block(chain_name, latest_block)
  end

  def process_block_deposits(block_number, chain_name, chain_config)
    block = get_block_with_transactions(block_number, chain_config[:quicknode_url])
    
    block['transactions'].each do |tx|
      next unless customer_address?(tx['to'])
      
      # Create deposit record with chain information
      create_deposit_record(tx, chain_name)
    end
  end

  def create_deposit_record(transaction, chain)
    currency = Currency.find_by(symbol: SUPPORTED_CHAINS[chain][:currency_code].upcase)
    payment_address = PaymentAddress.find_by(address: transaction['to'].downcase)
    
    Deposits::Coin.create!(
      currency: currency,
      member: payment_address.member,
      address: transaction['to'],
      txid: transaction['hash'],
      amount: wei_to_decimal(transaction['value']),
      block_number: transaction['blockNumber'].to_i(16),
      details: { 
        chain: chain,
        gas_used: transaction['gas'],
        gas_price: transaction['gasPrice']
      }
    )
  end
end
```

## 5. **Database Schema Updates**

Add chain tracking to your existing tables:

```ruby
# Migration to add chain support
class AddChainSupportToPaymentAddresses < ActiveRecord::Migration[6.1]
  def change
    add_column :payment_addresses, :supported_chains, :json, default: []
    add_column :deposits, :chain, :string
    add_column :withdrawals, :chain, :string
    
    add_index :deposits, :chain
    add_index :withdrawals, :chain
  end
end
```

## 6. **Configuration Setup**

```yaml
# config/credentials.yml.enc
ethereum:
  quicknode_url: "https://eth-mainnet.quiknode.pro/your-key/"
  
polygon:
  quicknode_url: "https://polygon-mainnet.quiknode.pro/your-key/"
  
bsc:
  quicknode_url: "https://bsc-mainnet.quiknode.pro/your-key/"
  
arbitrum:
  quicknode_url: "https://arb-mainnet.quiknode.pro/your-key/"

wallets:
  storage_dir: "/opt/peatio/wallets"
```

## 7. **Docker Compose Updates**

```yaml
# docker-compose.yml
services:
  peatio:
    environment:
      - ETHEREUM_QUICKNODE_URL
      - POLYGON_QUICKNODE_URL  
      - BSC_QUICKNODE_URL
      - ARBITRUM_QUICKNODE_URL
    volumes:
      - wallet_storage:/opt/peatio/wallets
      
  # Multi-chain deposit scanner
  deposit-scanner:
    image: your-peatio-image
    command: ["bundle", "exec", "rake", "deposit:scan_all_chains"]
    environment:
      - DATABASE_URL
      - REDIS_URL
    volumes:
      - wallet_storage:/opt/peatio/wallets
    depends_on:
      - database
      - redis
```

## 8. **Rake Tasks for Management**

```ruby
# lib/tasks/multi_chain.rake
namespace :wallet do
  desc "Create universal address for customer"
  task :create_address, [:member_id] => :environment do |t, args|
    member = Member.find(args[:member_id])
    
    # One address works for all supported chains
    SUPPORTED_CHAINS.each do |chain_name, config|
      currency = Currency.find_by(symbol: config[:currency_code].upcase)
      wallet = Wallet.find_by(currency: currency, kind: 'deposit')
      
      # Check if address already exists for this member/currency
      existing = PaymentAddress.find_by(member: member, wallet: wallet)
      
      unless existing
        address = wallet.create_address!(member: member)
        puts "Created #{chain_name} address for member #{member.id}: #{address}"
      else
        puts "#{chain_name} address already exists: #{existing.address}"
      end
    end
  end

  desc "Show wallet balance across all chains"
  task :check_balances, [:address] => :environment do |t, args|
    wallet_service = MultiChainEthereumWallet.new
    
    SUPPORTED_CHAINS.each do |chain_name, config|
      balance_wei = wallet_service.get_balance(args[:address], chain_name)
      balance_eth = balance_wei / 10**18.0
      
      puts "#{chain_name.upcase}: #{balance_eth} #{config[:currency_code].upcase}"
    end
  end
end

namespace :deposit do
  desc "Scan all chains for deposits"
  task scan_all_chains: :environment do
    scanner = MultiChainDepositScanner.new
    scanner.scan_all_chains
  end
  
  desc "Collect deposits from all chains"
  task collect_all: :environment do
    SUPPORTED_CHAINS.each do |chain_name, config|
      currency = Currency.find_by(symbol: config[:currency_code].upcase)
      wallet = Wallet.find_by(currency: currency, kind: 'deposit')
      
      puts "Collecting #{chain_name} deposits..."
      wallet.collect_deposits!
    end
  end
end
```

## 9. **Admin Interface Updates**

Add chain selection to your admin interface:

```ruby
# Admin controller for multi-chain operations
class Admin::MultiChainController < Admin::BaseController
  def wallet_overview
    @wallet_service = MultiChainEthereumWallet.new
    @addresses = PaymentAddress.includes(:member, :wallet)
    
    @balances = {}
    @addresses.each do |addr|
      @balances[addr.address] = {}
      SUPPORTED_CHAINS.each do |chain, config|
        @balances[addr.address][chain] = @wallet_service.get_balance(addr.address, chain)
      end
    end
  end

  def create_universal_address
    member = Member.find(params[:member_id])
    
    # Create address for all EVM chains
    SUPPORTED_CHAINS.each do |chain_name, config|
      currency = Currency.find_by(symbol: config[:currency_code].upcase)
      wallet = Wallet.find_by(currency: currency, kind: 'deposit')
      
      unless PaymentAddress.exists?(member: member, wallet: wallet)
        wallet.create_address!(member: member)
      end
    end
    
    redirect_back(fallback_location: admin_members_path)
  end
end
```

## 10. **Customer Benefits**

With this setup, customers get:

- **One address for multiple chains** - Same Ethereum address works on Polygon, BSC, Arbitrum
- **Unified wallet management** - Single interface for all EVM assets
- **Efficient operations** - Shared wallet files reduce storage and management overhead

## 11. **Migration Strategy**

1. **Phase 1:** Deploy multi-chain wallet service alongside existing Geth
2. **Phase 2:** Test on testnets (Goerli, Mumbai, BSC Testnet)
3. **Phase 3:** Create universal addresses for new customers
4. **Phase 4:** Migrate existing customers to universal addresses
5. **Phase 5:** Decomission Geth node

## 12. **Operational Advantages**

- **Reduced Infrastructure:** One VM instead of multiple nodes
- **Shared Wallet Files:** Same private key works across all chains
- **Unified Codebase:** One implementation for all EVM chains
- **Cost Efficiency:** QuickNode handles the heavy blockchain infrastructure

The key insight is that EVM compatibility means one wallet file can securely operate across dozens of blockchains, dramatically simplifying your infrastructure while expanding your supported assets.

Would you like me to detail the migration process for existing wallets, or elaborate on any specific aspect like the deposit scanning implementation?

