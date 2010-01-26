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
    def self.extended(base)
      name = base.to_s.split('::').last
      base.returns :fetchByVid, base
      base.returns :"fetchByMerchant#{name}Id", base
    end
    
    def coerce_returns_for(method, objects)
      @return_mappings[method].zip(objects).map do |c,o|
        case c
        when :boolean, :string
          o
        else
          c.new(o)
        end
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
    
    def find_by_merchant_id(id)
      self.send(:"fetchByMerchant#{self.to_s.split('::').last}Id", id)
    end
    
    def find_by_vid(id)
      fetchByVid(id)
    end

    def method_missing(method, *args)
      if args[0].kind_of? Hash
        args[0] = defaults_for(method).merge(args.first)
      end
      with_soap do |soap|
        objs = soap.send(method, Vindicia.auth, *args.clone)
        ret, *objs = coerce_returns_for(method, objs)
        objs.first.status = ret
        objs.size == 1 ? objs.first : objs
      end
    end
    
    def quietly
      # Squelch warnings on stderr
      stderr = $stderr
      $stderr = StringIO.new
      ret = yield
      $stderr = stderr
      ret
    end
    
    def returns(method, *classes)
      @return_mappings ||= Hash.new([Return])
      @return_mappings[method] += classes
    end
  
    def soap
      @soap ||= begin
        s = wsdl.create_rpc_driver
        # prodtest/staging wsdl are identical to production, so force a correct url
        s.proxy.instance_variable_set('@endpoint_url', Vindicia.endpoint)
        s.wiredump_dev = STDERR if $DEBUG
        s
      end
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
  
  class SoapObject
    attr_accessor :status
    
    def initialize(soap=nil)
      @values = {}
      soap.instance_variable_get('@__xmlele').each do |qname, value|
        @values[qname.name] = value
      end if soap
    end
    
    def method_missing(method, *args)
      if @values.has_key? method.to_s
        @values[method.to_s]
      else
        super
      end
    end
  end
  
  class Return
    attr_reader :code, :response
    def initialize(soap)
      @code = soap['returnCode'].to_i
      @response = soap['returnString']
    end
  end
  
  class Account < SoapObject
    extend SoapClient
    
    default :update, :emailTypePreference => 'plaintext'
    returns :update, Account, :boolean
    
    default :updatePaymentMethod, :emailTypePreference => 'plaintext'
  end
  
  class AutoBill < SoapObject
    extend SoapClient
  end

  class BillingPlan < SoapObject
    extend SoapClient
  end

  class Product < SoapObject
    extend SoapClient
  end

  # TODO:
  # Activity
  # Address
  # Chargeback
  # Entitlement
  # PaymentMethod
  # PaymentProvider
  # Refund
  # Transaction
  
end
