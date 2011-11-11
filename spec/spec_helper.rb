$:.push File.join(File.dirname(__FILE__), '..', 'lib')

require 'vindicia'
require 'fakeweb'

RSpec.configure do |config|
  config.mock_with :rspec
end

module Vindicia
  def self.set_bootstrapped(state = true)
    @bootstrapped = state
  end
end

Savon.configure do |config|
  config.log = false
end
def HTTPI.log(*args); end

Dir[File.dirname(__FILE__) + "/support/Vindicia_*.xsd"].each do |xsd|
  version = xsd.match(/Vindicia_(.+).xsd/)[1]
  FakeWeb.register_uri(:get, "http://soap.prodtest.sj.vindicia.com/#{version}/Vindicia.xsd",
                       :body => File.read(xsd))
end

Dir[File.dirname(__FILE__) + "/support/*_*.wsdl"].each do |wsdl|
  match = wsdl.match(/support\/(.+)_(.+)\.wsdl/)
  FakeWeb.register_uri(:get, 
      "http://soap.prodtest.sj.vindicia.com/#{match[2]}/#{match[1]}.wsdl",
      :body => File.read(wsdl))
end
