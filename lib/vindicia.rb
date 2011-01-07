require 'savon'
require 'savon_patches'

module Vindicia
  NAMESPACE = "http://soap.vindicia.com/Vindicia"

  class << self
    attr_reader :login, :password, :environment
    def authenticate(login, pass, env=:prodtest)
      @login       = login
      @password    = pass
      @environment = env.to_s
    end

    def version
      '3.4'
    end

    def auth
      {'version' => version, 'login' => login, 'password' => password}
    end

    def domain
      case @environment
      when 'prodtest'  ; "soap.prodtest.sj.vindicia.com"
      when 'staging'   ; "soap.staging.sj.vindicia.com"
      when 'production'; "soap.vindicia.com"
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
    def find(id)
      self.send(:"fetchByMerchant#{name}Id", id)
    end

    def method_missing(method, *args)
      with_soap do |soap|
        response = soap.request(:wsdl, method) do |soap, wsdl|
          keys = wsdl.arg_list["#{method}_in"].map{|arg|arg["name"]}
          soap.body = Hash[keys.zip([Vindicia.auth] + args)]
        end
        # TODO: Fix XML parsing - vindicia response does not define xsi namespace :(
        # TODO: wrap output objects in classes (maybe replace SoapObject with BasicObject subclass)
        objs = response.to_array
        pp Crack::XML.parse(response.to_xml)
        STDOUT.flush
        ret = objs.shift

        return [ret] + objs unless objs.first.is_a? SoapObject

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

    def name
      self.to_s.split('::').last
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

    def soap
      @soap ||= begin
        Savon::Client.new do |wsdl|
          wsdl.document = Vindicia.wsdl(name)
          # Test WSDL files contain production endpoints, must override
          wsdl.endpoint = Vindicia.endpoint

          # Be sure to parse arg lists for revification
          def wsdl.parser
            @parser ||= begin
              parser = WSDLParserWithArgList.new
              REXML::Document.parse_stream self.document, parser
              parser
            end
          end
        end
      end
    end

    def with_soap
      ret = quietly { yield soap }
      soap.reset_stream
      ret
    end
  end

  class SoapObject
    include Comparable
    attr_accessor :request_status

    def initialize(arg=nil)
      case arg
        when String
          instance_variable_set("@merchant#{classname}Id", arg)
        when Hash
          arg.each do |key, value|
            instance_variable_set("@#{key}", value)
          end
#        when SOAP::Mapping::Object
#          arg.instance_variable_get('@__xmlele').each do |qname, value|
#            instance_variable_set("@#{qname.name}", value)
#          end
      end
    end

    def VID
      # WSDL Driver conveniently downcases initial char
      self.vID
    end

    def classname
      self.class.name
    end

    def method_missing(method, *args)
      if instance_variable_defined?("@#{method}")
        instance_variable_get("@#{method}")
      else
        super
      end
    end

    # TODO: respond_to?

    def ref
      key = "merchant#{classname}Id"
      {key => instance_variable_get("@#{key}")}
    end

    def to_hash
      instance_variables.inject({}) do |result, ivar|
        name = ivar[1..-1]
        value = instance_variable_get(ivar)
        case value
        when SoapObject
          value = value.to_hash
        when Array
          value = value.map{|e| e.kind_of?(SoapObject) ? e.to_hash : e}
        end
        result[name] = value
        result
      end
    end
  end

  # API classes
  class Account           < SoapObject; extend SoapClient end
  class Activity          < SoapObject; extend SoapClient end
  class Address           < SoapObject; extend SoapClient end
  class AutoBill          < SoapObject; extend SoapClient end
  class BillingPlan       < SoapObject; extend SoapClient end
  class Chargeback        < SoapObject; extend SoapClient end
  class Entitlement       < SoapObject; extend SoapClient end
  class PaymentMethod     < SoapObject; extend SoapClient end
  class PaymentProvider   < SoapObject; extend SoapClient end
  class Product           < SoapObject; extend SoapClient end
  class Refund            < SoapObject; extend SoapClient end
  class Transaction       < SoapObject; extend SoapClient end

  # customized data classes
  class Return < SoapObject
    def code; self.returnCode.to_i; end
    def response; self.returnString; end
  end

  # Stub data types
  class ActivityCancellation          < SoapObject ; end
  class ActivityEmailContact          < SoapObject ; end
  class ActivityFulfillment           < SoapObject ; end
  class ActivityLogin                 < SoapObject ; end
  class ActivityLogout                < SoapObject ; end
  class ActivityNamedValue            < SoapObject ; end
  class ActivityNote                  < SoapObject ; end
  class ActivityPhoneContact          < SoapObject ; end
  class ActivityTypeArg               < SoapObject ; end
  class ActivityURIView               < SoapObject ; end
  class ActivityUsage                 < SoapObject ; end
  class Authentication                < SoapObject ; end
  class BillingPlanPeriod             < SoapObject ; end
  class BillingPlanPrice              < SoapObject ; end
  class Boleto                        < SoapObject ; end
  class CancelResult                  < SoapObject ; end
  class CaptureResult                 < SoapObject ; end
  class CreditCard                    < SoapObject ; end
  class DirectDebit                   < SoapObject ; end
  class ECP                           < SoapObject ; end
  class ElectronicSignature           < SoapObject ; end
  class EmailTemplate                 < SoapObject ; end
  class MerchantEntitlementId         < SoapObject ; end
  class MetricStatistics              < SoapObject ; end
  class NameValuePair                 < SoapObject ; end
  class PayPal                        < SoapObject ; end
  class SalesTax                      < SoapObject ; end
  class ScoreCode                     < SoapObject ; end
  class TaxExemption                  < SoapObject ; end
  class Token                         < SoapObject ; end
  class TokenAmount                   < SoapObject ; end
  class TokenTransaction              < SoapObject ; end
  class TransactionItem               < SoapObject ; end
  class TransactionStatus             < SoapObject ; end
  class TransactionStatusBoleto       < SoapObject ; end
  class TransactionStatusCreditCard   < SoapObject ; end
  class TransactionStatusDirectDebit  < SoapObject ; end
  class TransactionStatusECP          < SoapObject ; end
  class TransactionStatusPayPal       < SoapObject ; end
  class WebSession                    < SoapObject ; end
end

# class WSDL::XMLSchema::SimpleRestriction
#   def check_restriction(value)
#     @enumeration.empty? or @enumeration.include?(value) or value.nil?
#   end
# end
#
# module SOAP::Mapping
#   def self.const_from_name(name, lenient = false)
#     const = ::Object
#     # Monkeypatch below
#     # Scope unknown class lookups inside our namespace to
#     # prevent conflicts with applications defining their own
#     # Account, CreditCard, etc. classes.
#     const = ::Vindicia unless name =~ /\A::/
#     # Monkeypatch above
#     name.sub(/\A::/, '').split('::').each do |const_str|
#       if XSD::CodeGen::GenSupport.safeconstname?(const_str)
#         if const.const_defined?(const_str)
#           const = const.const_get(const_str)
#           next
#         end
#       elsif lenient
#         const_str = XSD::CodeGen::GenSupport.safeconstname(const_str)
#         if const.const_defined?(const_str)
#           const = const.const_get(const_str)
#           next
#         end
#       end
#       return nil
#     end
#     const
#   end
# end

if false
  # make above 'if true' to add debug output of XML going across the wire
  class SOAP::HTTPStreamHandler
    def send(endpoint_url, conn_data, soapaction = nil, charset = @charset)
      puts conn_data.send_string
      conn_data.soapaction ||= soapaction # for backward conpatibility
      send_post(endpoint_url, conn_data, charset)
    end
  end
end
