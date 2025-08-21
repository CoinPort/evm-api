require 'sinatra'
require 'rack/contrib'
require_relative './eth_tool'

set :bind, '0.0.0.0'

puts 
puts 'Starting Ethereum API...'

set :port, ENV.fetch('PORT', 3000)

puts "Listening on port: #{settings.port}"
puts 

use Rack::JSONBodyParser

# JSON-RPC interface for Peatio compatibility (root path)
post '/' do
  content_type :json
  
  request_body = JSON.parse(request.body.read)
  method = request_body['method']
  params = request_body['params'] || []
  id = request_body['id']
  
  puts "JSON-RPC call: #{method} with params: #{params}"
  
  begin
    puts "Processing method: #{method} with params: #{params.inspect}"
    result = handle_rpc_method(method, params)
    
    {
      jsonrpc: '2.0',
      result: result,
      id: id
    }.to_json
    
  rescue => e
    puts "RPC Error: #{e.message}"
    
    {
      jsonrpc: '2.0',
      error: {
        code: -32603,
        message: e.message
      },
      id: id
    }.to_json
  end
end

def handle_rpc_method(method, params)
  puts "Handling RPC method: #{method} with params: #{params.inspect}"
  case method
  when 'personal_newAccount'
    password = params[0]
    create_account(password)
    
  when 'eth_sendTransaction'
    # Peatio sends transaction parameters
    tx_params = params[0]
    address = tx_params['from']
    to = tx_params['to']
    value_wei = tx_params['value'].to_i(16)
    amount_eth = value_wei / 1e18.to_f
    
    # You'll need to get password from Peatio somehow
    # For now, assuming it's passed in a custom field
    password = tx_params['password']
    
    send_transaction(address, password, to, amount_eth)
    
  when 'personal_unlockAccount', 'personal_lockAccount'
    true # Return true for compatibility
    
  when 'personal_listAccounts'
    # Return list of addresses from keystore directory
    Dir.children(KEYSTORE_DIR).map do |filename|
      if filename.match(/UTC--.*--(.*)/)
        "0x#{$1}"
      end
    end.compact
    
  else
    # Forward other calls to QuickNode
    rpc_call(method, params)
  end
end

# REST API endpoints (keep existing functionality)
post '/create_account' do
  password = params['password']
  puts 'REST - create_account'
  return [400, { error: 'Missing password' }.to_json] unless password

  begin
    address = create_account(password)
    { address: address }.to_json
  rescue => e
    [500, { error: e.message }.to_json]
  end
end

post '/send_transaction' do
  puts 'REST - /send_transaction'

  address = params['address']
  password = params['password']
  to = params['to']
  amount = params['value']

  if !address || !password || !to || !amount
    return [400, { error: 'Missing required fields' }.to_json]
  end

  begin
    tx_hash = send_transaction(address, password, to, amount)
    { txHash: tx_hash }.to_json
  rescue => e
    [500, { error: e.message }.to_json]
  end
end