require 'savon'
require 'nokogiri'

require 'vindicia/bootstrap'
require 'vindicia/parser'


Savon.configure do |config|
  config.soap_version = 1
  # doing this to facilitate fallback
  config.raise_errors = false
end

module Vindicia

  class << self

    include Bootstrap
    attr_accessor :login, :password, :environment
    attr_accessor :version, :namespace
    alias :api_version= :version=

    def authenticate(login, pass, env=:prodtest)
      @login       = login
      @password    = pass
      @environment = env.to_s
    end

    def version
      @version || '3.6'
    end

    def namespace
      @namespace || 'http://soap.vindicia.com/Vindicia'
    end

    def endpoint=(endpoint)
      warn "Vindicia.endpoint= has been replaced with environment-based config. Use Vindicia.environment= instead."
    end

    # Add configuration block
    # &block - returns self for configuration.  Alternative to just auth 
    def configure
      yield self if block_given?
      bootstrap
    end

    def auth
      {'version' => version, 'login' => login, 'password' => password}
    end

    def domain(env = nil)
      case (env ? env : @environment)
      when 'production'; "soap.vindicia.com"
      when 'staging'   ; "soap.staging.sj.vindicia.com"
      when 'fallback'  ; "soap-alt.vindicia.com" 
      else             ; "soap.prodtest.sj.vindicia.com"
      end
    end

    def endpoint(env = nil)
      "https://#{domain(env)}/v#{version}/soap.pl"
    end

    def wsdl(object)
      "http://#{domain}/#{version}/#{object}.wsdl"
    end

    def silence_debug_output!
      Savon.configure do |config|
        config.log = false
      end
      def HTTPI.log(*args); end
    end

    def parse_response(soap_response, method_called)
      parser = Vindicia::Parser.new(soap_response, method_called)
      parser.parse
    end

  private
    def singularize(type)
      # Specifically formulated for just the ArrayOf types in Vindicia
      # The '!' is there to handle singularizing "ses" suffix correctly
      type.sub(/ArrayOf/,'').
        sub(/ies$/, 'y').
        sub(/([sx])es$/, '\1!').
        sub(/s$/, '').
        chomp('!')
    end
  end
end
