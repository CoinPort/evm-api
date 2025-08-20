require 'sinatra'
require 'rack/contrib'
require_relative './eth_tool'

set :bind, '0.0.0.0'

puts '.'
puts 'Starting Ethereum API...'

set :port, ENV.fetch('PORT', 3000)

puts "Listening on port: #{settings.port}"
puts '.'

use Rack::JSONBodyParser

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