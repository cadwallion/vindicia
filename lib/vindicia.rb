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
  
  module SoapClient
    def soap
      @soap ||= begin
        s = wsdl.create_rpc_driver
        # prodtest/staging wsdl are identical to production, so force a correct url
        s.proxy.instance_variable_set('@endpoint_url', Vindicia.endpoint)
        s.wiredump_dev = STDERR if $DEBUG
        s
      end
    end

    def method_missing(method, *args)
      if args[0].kind_of? Hash
        args[0] = defaults_for(method).merge(args.first)
      end
      with_soap do |soap|
        soap.send(method, Vindicia.auth, *args.clone)
      end
    end
    
    def default(method, defaults)
      @defaults ||= {}
      @defaults[method] = defaults
    end
    
    def defaults_for(method)
      @defaults ||= {}
      @defaults[method] || {}
    end

    def quietly
      # Squelch warnings on stderr
      stderr = $stderr
      $stderr = StringIO.new
      ret = yield
      $stderr = stderr
      ret
    end
  
    def with_soap
      ret = quietly { yield soap }
      soap.reset_stream
      ret
    end
  
    def wsdl
      @wsdl ||= quietly do
        SOAP::WSDLDriverFactory.new(Vindicia.wsdl(self.to_s.split('::').last))
      end
    end
  end
  
  class Account
    extend SoapClient
    default :update, :emailTypePreference => 'plaintext'
  end
  
  # class Activity
  #   extend SoapClient
  # end
  # 
  # class Address
  #   extend SoapClient
  # end

  class AutoBill
    extend SoapClient
  end

  class BillingPlan
    extend SoapClient
  end

  # class Chargeback < SoapClient ; end
  # class Entitlement < SoapClient ; end
  # class PaymentMethod < SoapClient ; end
  # class PaymentProvider < SoapClient ; end
  class Product
    extend SoapClient
  end

  # class Refund < SoapClient ; end
  # class Transaction < SoapClient ; end
  
end
