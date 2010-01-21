require 'soap/wsdlDriver'

module Vindicia
  class << self
    attr_reader :login, :password
    def authenticate(login, pass, env=:prodtest)
      @login       = login
      @password    = pass
      @environment = env
    end
    
    def version
      '3.4'
    end

    def auth
      {'version' => version, 'login' => login, 'password' => password}
    end
    
    def domain
      case @environment
      when :prodtest  ; "soap.prodtest.sj.vindicia.com"
      when :staging   ; "soap.staging.sj.vindicia.com"
      when :production; "soap.vindicia.com"
      end
    end
    
    def endpoint
      "https://#{domain}/v#{version}/soap.pl"
    end
    
    def wsdl(object)
      "http://#{domain}/#{version}/#{object}.wsdl"
    end
  end
  
  class SoapClient
    attr_reader :wsdl_, :soap
    
    def initialize(test=true)
      @class = self.class.to_s.split('::').last
      @login = Vindicia.login
      @password = Vindicia.password
    
      @soap = wsdl.create_rpc_driver
      # prodtest/staging wsdl are identical to production, so force a correct url
      @soap.proxy.instance_variable_set('@endpoint_url', Vindicia.endpoint)
      @soap.wiredump_dev = STDERR if $DEBUG
    end

    def method_missing(method, *args)
      if args[0].kind_of? Hash
        args[0] = self.class.defaults_for(method).merge(args.first)
      end
      with_soap do |soap|
        soap.send(method, Vindicia.auth, *args)
      end
    end
    
    def self.default(method, defaults)
      @defaults ||= {}
      @defaults[method] = defaults
    end
    
    def self.defaults_for(method)
      @defaults ||= {}
      @defaults[method] || {}
    end

  private
    def quietly
      # Squelch warnings on stderr
      stderr = $stderr
      $stderr = StringIO.new
      ret = yield
      $stderr = stderr
      ret
    end
  
    def with_soap
      ret = quietly { yield @soap }
      @soap.reset_stream
      ret
    end
  
    def wsdl
      @@wsdl_ ||= quietly do
        SOAP::WSDLDriverFactory.new(Vindicia.wsdl(@class))
      end
    end
  end
  
  class Account < SoapClient
    default :update, :emailTypePreference => 'plaintext'
  end
  
  class Activity < SoapClient ; end
  class Address < SoapClient ; end
  class AutoBill < SoapClient ; end
  class BillingPlan < SoapClient ; end
  class Chargeback < SoapClient ; end
  class Entitlement < SoapClient ; end
  class PaymentMethod < SoapClient ; end
  class PaymentProvider < SoapClient ; end
  class Product < SoapClient ; end
  class Refund < SoapClient ; end
  class Transaction < SoapClient ; end
  
end
