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

    def sequence
      @seq ||= 0
    end
    def sequence_reset
      @seq = 0
    end
    def sequence_next
      @seq ||= 0
      @seq += 1
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
        else
          raise "Unknown type for #{arg.class}:#{arg.inspect}"
      end
    end
  end

  module SoapClient
    def find(id)
      self.send(:"fetch_by_merchant_#{name.downcase}_id", id)
    end

    def method_missing(method, *args)
      method = underscore(method.to_s).to_sym # back compatability from camelCase api
      out_vars = nil # set up outside variable

      Vindicia.sequence_reset
      Vindicia.sequence_next
      response = soap.request(:n1, method) do |soap, wsdl|
        out_vars = wsdl.arg_list["#{method.to_s.lower_camelcase}_out"]
        soap.body = begin
          xml = Builder::XmlMarkup.new

          key = "#{method.to_s.lower_camelcase}_in"
          wsdl.arg_list[key].zip([Vindicia.auth] + args).each do |arg, data|
            case data
            when Hash
              begin
                obj = Vindicia.const_get(arg["type"].split(':').last).new(data)
                obj.build(xml, arg["name"])
              rescue
                data
              end
            when SoapObject
              data.build(xml, arg["name"])
            else
              opts = if data.nil?
                {"xsi:nil" => true}
              else
                {"xsi:type" => Vindicia.type_of(data)} #arg["type"]}
              end
              xml.tag!(arg["name"], data, opts)
            end
          end

          xml.target!
        end
      end

      values = response.to_hash[:"#{method}_response"]
      objs = out_vars.map do |var|
        value = values[var["name"].to_sym]
        Vindicia.const_get(value[:type].split(':').last).new(value) rescue value
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

    # def r_merge
    #   @r_merge ||= proc do |key,v1,v2|
    #     Hash === v1 && Hash === v2 ? v1.merge(v2, &r_merge) : v2
    #   end
    # end

    # def required(*fields)
    #   @required_fields = fields
    # end
    # def required_fields
    #   @required_fields || []
    # end

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
    include Comparable
    attr_accessor :request_status

    def attributes
      key = self.class.to_s.split('::').last
      @attributes ||= Vindicia.xsd(key).inject({}) do |memo, attr|
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
          # pull out namespaced values, leave "real" values for CreditCard (+others?)
          value = [value].flatten.reject{|e|e =~ /:/}.first
          next if value.nil?
        end
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
      xml.tag!(tag, soap_type_info) do |xml|
        attributes.each do |name, type|
          next if name == 'vid'

          value = instance_variable_get("@#{underscore(name)}") || instance_variable_get("@#{name}")

          if value.nil?
            #next if attribute["minOccurs"] == '0'
            attr = {"xsi:nil" => true} if value.nil?
            xml.tag!(name, attr, value)
            next
          end

          class_name = type.split(':').last
          if type =~ /tns:/ and Vindicia.const_defined?(class_name)
            klass = Vindicia.const_get(class_name)
            klass.new(value).build(xml, name)
            next
          end

          if value.kind_of? Hash
            puts "hash, not object (#{type}):"
            xml.tag!(name) do |x|
              value.each do |k,v|
                p [k,v]
                if v
                  # this xsi:type is optional
                  x.tag!(k, {"xsi:type" => Vindicia.type_of(v)}, v)
                else
                  x.tag!(k, {"xsi:nil" => "true"})
                end
              end
            end
          else
            xml.tag!(name, {"xsi:type" => Vindicia.type_of(value)}, value)
          end
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

      class_name = type.split(':').last
      if Vindicia.const_defined?(class_name)
        obj = Vindicia.const_get(class_name).new(value)
        yield obj if block_given?
        return obj
      else
        value
      end
    end

    def classname
      self.class.name
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

    def method_missing(method, *args)
      method = underscore(method.to_s).to_sym # back compatability from camelCase api
      key = camelcase(method.to_s)

      if attributes[key]
        val = instance_variable_get("@#{method}")
        if val.kind_of?(Hash) && val.key?(:array_type)
          val = [val[method]].flatten.map do |e|
            cls = e[:type].last.split(':').last
            if Vindicia.const_defined?(cls)
              Vindicia.const_get(cls).new(e)
            else
              e
            end
          end
        end
        val
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

    def soap_type_info(type=nil)
      type ||= classname.split('::').last
      ns = Vindicia.sequence_next
      { "xsi:type" => "n#{ns}:#{type}",
        "xmlns:n#{ns}" => "http://soap.vindicia.com/Vindicia" }
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
      type.sub(/ies$/, 'y')
      type.sub(/([sx])es$/, '\1')
      type.sub(/s$/, '')
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
