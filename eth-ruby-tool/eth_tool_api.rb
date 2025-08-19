require 'sinatra'
require 'rack/contrib'
require_relative './eth_tool'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 8545)
use Rack::JSONBodyParser

post '/create_account' do
  password = params['password']
  return [400, { error: 'Missing password' }.to_json] unless password

  begin
    address = create_account(password)
    { address: address }.to_json
  rescue => e
    [500, { error: e.message }.to_json]
  end
end

post '/send_transaction' do
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