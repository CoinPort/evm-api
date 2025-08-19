# lib/blockchain_config.rb
require 'yaml'

class BlockchainConfig
  CONFIG_FILE = '/opt/config/blockchain-config.yml'
  
  def self.load
    puts 'pmc Loading blockchain configuration...'
    @config ||= YAML.load_file(CONFIG_FILE)
  end
  
  def self.for_chain(chain_name)
    puts "pmc Loading configuration for chain: #{chain_name}"
    
    raise ArgumentError, "Chain name must be a symbol or string" unless chain_name.is_a?(Symbol) || chain_name.is_a?(String)
    
    # Load the entire config and then filter for the specific chain
    return {} unless File.exist?(CONFIG_FILE)
    
    # Load the config file
    config = load
    chain_config = config['chains'][chain_name.to_s]
    global_config = config['global']
    
    raise "Chain not configured: #{chain_name}" unless chain_config
    
    # Merge chain-specific with global settings
    global_config.merge(chain_config)
  end
  
  def self.all_chains
    puts 'pmc Loading all configured chains...'
    load['chains'].keys.map(&:to_sym)
  end
  
  def self.global
    puts 'pmc Loading global configuration...'
    raise "Global configuration not found" unless load['global']
    load['global']
  end
end

