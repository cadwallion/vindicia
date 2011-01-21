require 'savon'
require 'savon_patches'
require 'httpclient'

Savon.configure do |config|
  config.log = false            # disable logging
  #config.log_level = :info      # changing the log level
  #config.logger = Rails.logger  # using the Rails logger
  config.soap_version = 1
end

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
      when 'production'; "soap.vindicia.com"
      when 'staging'   ; "soap.staging.sj.vindicia.com"
      else             ; "soap.prodtest.sj.vindicia.com"
      end
    end

    def endpoint
      "https://#{domain}/v#{version}/soap.pl"
    end

    def xsd(klass)
      require 'open-uri'
      url = "http://#{domain}/#{version}/Vindicia.xsd"
      @xsd_data ||= begin
        doc = REXML::Document.new(open(url).read)
        doc.root.get_elements("//xsd:complexType").inject({}){|memo, node|
          memo[node.attributes["name"]] = node.get_elements("xsd:sequence/xsd:element").map{|e|e.attributes}
          memo
        }
      end
      @xsd_data[klass]
    end

    def wsdl(object)
      "http://#{domain}/#{version}/#{object}.wsdl"
    end

    def class(type)
      klass = type.split(':').last
      klass = singularize($1) if klass =~ /^ArrayOf(.*)$/
      Vindicia.const_get(klass) rescue nil
    end

    def type_of(arg)
      case arg
        when TrueClass, FalseClass
          'xsd:boolean'
        when String
          'xsd:string'
        when Fixnum
          'xsd:int'
        when Float #, Decimal
          'xsd:decimal'
        # TODO: 'xsd:long'
        when Date, DateTime, Time
          'xsd:dateTime'
        #TODO: 'xsd:anyURI'
        when SoapObject
          "wsdl:#{arg.classname}"
        else
          raise "Unknown type for #{arg.class}~#{arg.inspect}"
      end
    end

    def coerce(name, type, value)
      return value if value.kind_of? SoapObject

      case type
      when /ArrayOf/
        return [] if value.nil?
        if value.kind_of? Hash
          if value[name.to_sym]
            return coerce(name, type, [value[name.to_sym]].flatten)
          else
            value = [value]
          end
        end
        value.map do |val|
          coerce(name, singularize(type), val)
        end
      when /^namesp/, /^vin/
        type = value[:type] if value.kind_of? Hash
        Vindicia.class(type).new(value)
      when "xsd:int"
        value.to_i
      else
        value
      end
    end

  private
    def singularize(type)
      # Specifically formulated for just the ArrayOf types in Vindicia
      type.sub(/ArrayOf/,'').
        sub(/ies$/, 'y').
        sub(/([sx])es$/, '\1').
        sub(/s$/, '')
    end
  end

  module XMLBuilder
    def build_xml(xml, name, type, value)
      if value.kind_of? Array
        build_array_xml(xml, name, type, value)
      else
        build_tag_xml(xml, name, type, value)
      end
    end

    def build_array_xml(xml, name, type, value)
      attrs = {
        "xmlns:enc" => "http://schemas.xmlsoap.org/soap/encoding/",
        "xsi:type" => "enc:Array",
        "enc:arrayType" => "vin:#{name}[#{value.size}]"
      }
      xml.tag!(name, attrs) do |x|
        value.each do |val|
          build_tag_xml(x, 'item', type, val)
        end
      end
    end

    def build_tag_xml(xml, name, type, value)
      case value
      when Hash
        Vindicia.class(type).new(value).build(xml, name)
      when SoapObject
        value.build(xml, name)
      when NilClass
        xml.tag!(name, value, {"xsi:nil" => true})
      else
        type = type.sub(/^tns/,'vin')
        xml.tag!(name, value, {"xsi:type" => type})
      end
    end
  end

  module SoapClient
    include XMLBuilder

    def find(id)
      self.send(:"fetch_by_merchant_#{name.downcase}_id", id)
    end

    def method_missing(method, *args)
      # TODO: verify that this method _is_ a method callable on the wsdl,
      #       and defer to super if not.
      method = underscore(method.to_s).to_sym # back compatability from camelCase api
      out_vars = nil # set up outside variable

      response = soap.request(:wsdl, method) do |soap, wsdl|
        out_vars = wsdl.arg_list["#{method.to_s.lower_camelcase}_out"]

        soap.namespaces["xmlns:vin"] = Vindicia::NAMESPACE
        soap.body = begin
          xml = Builder::XmlMarkup.new

          key = "#{method.to_s.lower_camelcase}_in"
          wsdl.arg_list[key].zip([Vindicia.auth] + args).each do |arg, data|
            build_xml(xml, arg['name'], arg['type'], data)
          end

          xml.target!
        end
      end

      values = response.to_hash[:"#{method}_response"]
      objs = out_vars.map do |var|
        value = values[underscore(var["name"]).to_sym]
        Vindicia.coerce(var["name"], var["type"], value)
      end

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

    def name
      self.to_s.split('::').last
    end

    def soap
      @soap ||= begin
        Savon::Client.new do |wsdl|
          wsdl.document = Vindicia.wsdl(name)
          # Test WSDL files contain production endpoints, must override
          wsdl.endpoint = Vindicia.endpoint

          # Be sure to parse arg lists for revification w/ custom parser
          def wsdl.parser
            @parser ||= begin
              parser = Savon::WSDL::ParserWithArgList.new
              REXML::Document.parse_stream self.document, parser
              parser
            end
          end
        end
      end
    end

  private
    def underscore(camel_cased_word)
      word = camel_cased_word.to_s.dup
      word.gsub!(/::/, '/')
      word.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
      word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word
    end
  end

  class SoapObject
    include XMLBuilder
    include Comparable
    attr_accessor :request_status

    def attributes
      @attributes ||= Vindicia.xsd(classname).inject({}) do |memo, attr|
        memo[attr["name"]] = attr["type"]
        memo["vid"] = attr["type"] if attr["name"] == "VID" # oh, casing
        memo
      end
    end

    def initialize(arg=nil)
      case arg
      when String, nil
        arg = {"merchant#{classname}Id" => arg}
      when Array
        arg = Hash[arg]
      end

      arg.each do |key, value|
        if key == :type
          # XML->Hash conversion causes conflict between 'type' metadata
          # and 'type' data field in CreditCard (+others?)
          # so extract the value we want.
          value = [value].flatten.reject{|e|e =~ /:/}.first
          next if value.nil?
        end
        # skip metadata
        next if [:xmlns, :array_type].include? key
        type = attributes[camelcase(key.to_s)]
        cast_as_soap_object(type, value) do |obj|
          value = obj
        end

        key = underscore(key) # old camelCase back-compat
        instance_variable_set("@#{key}", value)
      end
    end

    def build(xml, tag)
      xml.tag!(tag, {"xsi:type" => "vin:#{classname}"}) do |xml|
        attributes.each do |name, type|
          next if name == 'vid'

          value = instance_variable_get("@#{underscore(name)}") || instance_variable_get("@#{name}")
          build_xml(xml, name, type, value)
        end
      end
    end
    
    def cast_as_soap_object(type, value)
      return nil if type.nil? or value.nil?
      return value unless type =~ /tns:/

      if type =~ /ArrayOf/
        type = singularize(type.sub('ArrayOf',''))

        if value.kind_of?(Hash) && value[:array_type]
          key = value.keys - [:type, :array_type, :xmlns]
          value = value[key.first]
        end
        value = [value] unless value.kind_of? Array

        ary = value.map{|e| cast_as_soap_object(type, e) }
        yield ary if block_given?
        return ary
      end

      if klass = Vindicia.class(type)
        obj = klass.new(value)
        yield obj if block_given?
        return obj
      else
        value
      end
    end

    def classname
      self.class.to_s.split('::').last
    end

    def each
      attributes.each do |attr, type|
        value = self.send(attr)
        yield attr, value if value
      end
    end

    def key?(k)
      attributes.key?(k.to_s)
    end

    def type(*args)
      # type is deprecated, override so that it does a regular attribute lookup
      method_missing(:type, *args)
    end

    def method_missing(method, *args)
      attr = underscore(method.to_s).to_sym # back compatability from camelCase api
      key = camelcase(attr.to_s)

      if attributes[key]
        Vindicia.coerce(key, attributes[key], instance_variable_get("@#{attr}"))
      else
        super
      end
    end

    # TODO: respond_to?

    def ref
      key = instance_variable_get("@merchant#{classname}Id")
      ukey = instance_variable_get("@merchant_#{underscore(classname)}_id")
      {"merchant#{classname}Id" => ukey || key}
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

  private
    def underscore(camel_cased_word)
      word = camel_cased_word.to_s.dup
      word.gsub!(/::/, '/')
      word.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
      word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word
    end

    def camelcase(underscored_word)
      underscored_word.gsub(/_(.)/) do |m| m.upcase.sub('_','') end
    end

    def singularize(type)
      # Specifically formulated for just the ArrayOf types in Vindicia
      type.sub(/ies$/, 'y').
        sub(/([sx])es$/, '\1').
        sub(/s$/, '')
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
    def code; self.return_code.to_i; end
    def response; self.return_string; end
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
