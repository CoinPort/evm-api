require 'eth'
require 'fileutils'
require 'json'
require 'time'
require 'yaml'
require 'net/http'
require 'uri'

# Load configuration from YAML file or environment variables
def load_config
  config_file = '/opt/config/config.yml'
  
  if File.exist?(config_file)
    config = YAML.load_file(config_file)
    puts "Loaded config from #{config_file}"
  else
    config = {}
    puts "No config file found, using environment variables"
  end
  
  # Environment variables override config file values
  {
    quicknode_url: ENV['ETH_RPC_URL'] || config['quicknode_url'] || 'https://dry-wispy-gas.quiknode.pro',
    chain_id: ENV['CHAIN_ID']&.to_i || config['chain_id'] || 1,
    gas_limit: ENV['GAS_LIMIT']&.to_i || config['gas_limit'] || 21000,
    min_gas_price: ENV['MIN_GAS_PRICE']&.to_i || config['min_gas_price'] || nil
  }
end

# Load configuration once at startup
CONFIG = load_config

KEYSTORE_DIR = ENV['KEYSTORE_DIR'] || File.join(__dir__, 'keystores')

FileUtils.mkdir_p(KEYSTORE_DIR) unless Dir.exist?(KEYSTORE_DIR)

puts "Using KEYSTORE_DIR: #{KEYSTORE_DIR}"
puts "Using QuickNode URL: #{CONFIG[:quicknode_url]}"
puts "Using Chain ID: #{CONFIG[:chain_id]}"
puts "Using Gas Limit: #{CONFIG[:gas_limit]}"
puts "Using Min Gas Price: #{CONFIG[:min_gas_price]}"
puts

def get_utc_filename(address)
  now = Time.now.utc
  iso = now.iso8601.gsub(':', '-')
  "UTC--#{iso}--#{address.downcase}"
end

def rpc_call(method, params = [])
  puts
  uri = URI(CONFIG[:quicknode_url])
  puts "RPC call: #{method} to #{CONFIG[:quicknode_url]}"

  body = { jsonrpc: '2.0', method: method, params: params, id: 1 }.to_json
  response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
  result = JSON.parse(response.body)
  
  if result['error']
    raise "RPC Error: #{result['error']['message']}"
  end
  
  result['result']
end

def rpc_call_eth(method, params = [])
  rpc_call(method, params)
end

def create_account(password)
  puts
  puts 'Creating account...'
  raise ArgumentError, "Password cannot be empty" if password.nil? || password.empty?

  key = Eth::Key.new
  keystore = Eth::Key::Encrypter.perform(key, password)

  filename = get_utc_filename(key.address.to_s)
  path = File.join(KEYSTORE_DIR, filename)
  File.write(path, keystore)
  
  puts "Created account: #{key.address}"
  key.address.to_s
end

def send_transaction(address, password, to, amount_eth)
  puts 
  puts "Sending transaction from #{address} to #{to}, amount: #{amount_eth}"
  raise ArgumentError, "Invalid recipient address" unless to.match?(/^0x[a-fA-F0-9]{40}$/)
  raise ArgumentError, "Invalid amount" unless amount_eth.to_s.match?(/^\d+(\.\d+)?$/) && amount_eth.to_f > 0

  filename = Dir.children(KEYSTORE_DIR).find { |f| f.end_with?(address.downcase) }
  raise "Keystore not found in #{KEYSTORE_DIR} for address #{address}" unless filename

  path = File.join(KEYSTORE_DIR, filename)
  puts "Loading keystore from: #{path}"
  json = File.read(path)
  puts "Keystore loaded successfully#{json.inspect}, password: #{password.inspect}"
  puts

  begin
    key = Eth::Key::Decrypter.perform(json, password)
  rescue StandardError => e
    raise "Failed to load keystore: #{e.message}"
  end

  nonce = rpc_call_eth('eth_getTransactionCount', [key.address, 'pending']).to_i(16)
  gas_price = rpc_call_eth('eth_gasPrice').to_i(16)
  
  # Use minimum gas price from config if specified
  if CONFIG[:min_gas_price] && gas_price < CONFIG[:min_gas_price]
    gas_price = CONFIG[:min_gas_price]
    puts "Using minimum gas price: #{gas_price}"
  end

  tx = Eth::Tx.new(
    nonce: nonce,
    gas_price: gas_price,
    gas_limit: CONFIG[:gas_limit],
    to: to,
    value: Eth::Utils.to_wei(amount_eth.to_f),
    chain_id: CONFIG[:chain_id]
  )

  begin
    tx.sign(key)
  rescue StandardError => e
    puts "Failed to sign transaction: #{e.message}"
    raise "Failed to sign transaction: #{e.message}"
  end

  raw_tx = '0x' + RLP.encode(tx).unpack1('H*')
  tx_hash = rpc_call_eth('eth_sendRawTransaction', [raw_tx])

  unless tx_hash.is_a?(String) && tx_hash.match?(/^0x([A-Fa-f0-9]{64})$/)
    raise "Invalid transaction hash format: #{tx_hash.inspect}"
  end

  puts "Transaction hash: #{tx_hash}"
  tx_hash
end
