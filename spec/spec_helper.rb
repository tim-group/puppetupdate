$: << File.join([File.dirname(__FILE__), "lib"])

require 'rubygems'
require 'rspec'
require 'mcollective/test'
require 'rspec/mocks'
require 'mocha'
require 'tempfile'

module MCollective::Test::Util::Validator
  def self.validate
    false
  end
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.include(MCollective::Test::Matchers)

  config.before :each do
    MCollective::PluginManager.clear
  end
end
