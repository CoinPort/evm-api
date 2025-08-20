require 'eth'
require 'fileutils'
require 'json'
require 'time'

KEYSTORE_DIR = ENV['KEYSTORE_DIR'] || File.join(__dir__, 'keystores')

puts "pmc - Using KEYSTORE_DIR: #{KEYSTORE_DIR}"

FileUtils.mkdir_p(KEYSTORE_DIR) unless Dir.exist?(KEYSTORE_DIR)

puts "pmc - Using ETH_RPC_URL: #{ETH_RPC_URL}"

def get_utc_filename(address)
  puts 'pmc - get_utc_filename'
  now = Time.now.utc
  iso = now.iso8601.gsub(':', '-')
  "UTC--#{iso}--#{address.downcase}"
end

def rpc_call(method, params = [])
  uri = URI(ENV['ETH_RPC_URL'] || 'https://dry-wispy-gas.quiknode.pro')
  # pmc uri = URI(ENV['ETH_RPC_URL'] || 'http://geth:8545')

  puts 'pmc - rpc_call: #{uri}'

  body = { jsonrpc: '2.0', method: method, params: params, id: 1 }.to_json
  response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
  JSON.parse(response.body)['result']
end

def rpc_call_eth(method, params = [])
  puts 'pmc - rpc_call_eth'
  uri = URI('https://dry-wispy-gas.quiknode.pro')
  body = { jsonrpc: '2.0', method: method, params: params, id: 1 }.to_json
  response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
  JSON.parse(response.body)['result']
end

def create_account(password)
  puts 'pmc - create_account'
  raise ArgumentError, "Password cannot be empty" if password.nil? || password.empty?

  key = Eth::Key.new
  keystore = Eth::Key::Encrypter.perform(key, password)

  filename = get_utc_filename(key.address.to_s)
  path = File.join(KEYSTORE_DIR, filename)
  File.write(path, keystore)
  key.address.to_s
end

def send_transaction(address, password, to, amount_eth)
  puts 'pmc - send_transaction'
  raise ArgumentError, "Invalid recipient address" unless to.match?(/^0x[a-fA-F0-9]{40}$/)
  raise ArgumentError, "Invalid amount" unless amount_eth.to_s.match?(/^\d+(\.\d+)?$/) && amount_eth.to_f > 0

  filename = Dir.children(KEYSTORE_DIR).find { |f| f.end_with?(address.downcase) }
  raise "Keystore not found for address #{address}" unless filename

  path = File.join(KEYSTORE_DIR, filename)
  json = File.read(path)

  begin
    key = Eth::Key::Decrypter.perform(json, password)
  rescue StandardError => e
    raise "Failed to load keystore: #{e.message}"
  end

  nonce = rpc_call_eth('eth_getTransactionCount', [key.address, 'pending']).to_i(16)
  gas_price = rpc_call_eth('eth_gasPrice').to_i(16)

  tx = Eth::Tx.new(
    nonce: nonce,
    gas_price: gas_price,
    gas_limit: 21_000,
    to: to,
    value: Eth::Utils.to_wei(amount_eth.to_f)
  )

  begin
    tx.sign(key)
  rescue StandardError => e
    puts "pmc - Failed to sign transaction: #{e.message}"
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
