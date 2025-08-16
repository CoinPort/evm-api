# lib/blockchain_config.rb
require 'yaml'

class BlockchainConfig
  CONFIG_FILE = '/opt/config/blockchain-config.yml'
  
  def self.load
    @config ||= YAML.load_file(CONFIG_FILE)
  end
  
  def self.for_chain(chain_name)
    config = load
    chain_config = config['chains'][chain_name.to_s]
    global_config = config['global']
    
    raise "Chain not configured: #{chain_name}" unless chain_config
    
    # Merge chain-specific with global settings
    global_config.merge(chain_config)
  end
  
  def self.all_chains
    load['chains'].keys.map(&:to_sym)
  end
  
  def self.global
    load['global']
  end
end

