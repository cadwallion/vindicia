require 'soap/wsdlDriver'

module Vindicia
  class << self
    attr_reader :login, :password, :environment
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
        when :boolean, :string, :date
          o
        when :decimal
          o.to_i
        else
          c.new(o)
        end
      end
    end
    
    def default(method, *defaults)
      @defaults ||= {}
      @defaults[method] = defaults
    end
    
    def defaults_for(method)
      @defaults ||= {}
      @defaults[method] || []
    end
    
    def find_by_merchant_id(id)
      self.send(:"fetchByMerchant#{self.to_s.split('::').last}Id", id)
    end
    
    def find_by_vid(id)
      fetchByVid(id)
    end

    def method_missing(method, *args)
      # Need to make args and defaults the same size to zip() properly
      defaults = defaults_for(method)
      defaults << nil while defaults.size < args.size
      args << nil while args.size < defaults.size
      
      opts = args.zip(defaults).map do |arg, default|
        default.is_a?(Hash) ? default.merge(arg||{}, &r_merge) : arg || default
      end
      
      with_soap do |soap|
        objs = soap.send(method, Vindicia.auth, *opts)
        ret, *objs = coerce_returns_for(method, objs)
        case objs.size
        when 0
          ret.request_status = ret
          ret
        when 1
          objs.first.request_status = ret
          objs.first
        else
          objs.first.request_status = ret
          objs
        end
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
    
    def r_merge
      @r_merge ||= proc do |key,v1,v2|
        Hash === v1 && Hash === v2 ? v1.merge(v2, &r_merge) : v2
      end
    end
    
    def required(*fields)
      @required_fields = fields
    end
    def required_fields
      @required_fields || []
    end
    
    def returns(method, *classes)
      @return_mappings ||= Hash.new([Return])
      @return_mappings[method] += classes
    end
  
    def soap
      @soap ||= begin
        s = wsdl.create_rpc_driver
        # prodtest/staging wsdl point to production urls, so correct them
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
    attr_accessor :request_status, :values
    
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
    
    # TODO: respond_to?
    
    def vid
      self.VID
    end

    def vid_reference
      (self.class.required_fields + [:VID]).inject({}){|h,k| h[k] = @values[k.to_s]; h}
    end
  end
  
  class Return < SoapObject
    def code; self.returnCode.to_i; end
    def response; self.returnString; end
  end

  class TransactionStatus < SoapObject ; end
  
  class Account < SoapObject
    extend SoapClient
    
    returns :update, Account, :boolean
    
    default :updatePaymentMethod, {}, {}, true, 'Update', nil
    returns :updatePaymentMethod, Account, :boolean
  end
  
  class AutoBill < SoapObject
    extend SoapClient
    
    default :update, {}, 'Fail', true, 100
    returns :update, AutoBill, :boolean, TransactionStatus, :date, :decimal, :string
  end

  class BillingPlan < SoapObject
    extend SoapClient
    
    required :status
  end

  class Product < SoapObject
    extend SoapClient
    
    required :status, :taxClassification
  end
  
  class Transaction < SoapObject
    extend SoapClient

    default :auth, {}, 100, false
  end

  # TODO:
  # Activity
  # Address
  # Chargeback
  # Entitlement
  # PaymentMethod
  # PaymentProvider
  # Refund
  
end

class WSDL::XMLSchema::SimpleRestriction
  def check_restriction(value)
    @enumeration.empty? or @enumeration.include?(value) or value.nil?
  end
end
