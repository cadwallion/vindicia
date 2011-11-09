require 'savon'
require 'savon_patches'
require 'time'
require 'vindicia/xml_builder'
require 'vindicia/data_types'
require 'vindicia/soap_object'
require 'vindicia/soap_client'
require 'vindicia/api_classes'

Savon.configure do |config|
  config.soap_version = 1
end

module Vindicia
  class << self
    attr_reader :login, :password, :environment
    attr_accessor :version, :namespace

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

    # Add configuration block
    # &block - returns self for configuration.  Alternative to just auth 
    def configure
      yield self if block_given?
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

    def silence_debug_output!
      Savon.configure do |config|
        config.log = false
      end
      def HTTPI.log(*args); end
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
          return [] if value[:array_type] =~ /\[0\]$/
          if value[name.to_sym]
            return coerce(name, type, [value[name.to_sym]].flatten)
          else
            value = [value]
          end
        end
        value.map do |val|
          coerce(name, singularize(type), val)
        end
      when /^namesp/, /^vin/, /^tns/
        type = value[:type] if value.kind_of? Hash
        if klass = Vindicia.class(type)
          klass.new(value)
        else
          value
        end
      when "xsd:string"
        if value == {:type=>"xsd:string", :xmlns=>""}
          nil
        else
          value
        end
      when "xsd:int"
        value.to_i
      else
        value
      end
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

  # customized data classes
  class Return < SoapObject
    def code; self.return_code.to_i; end
    def response; self.return_string; end
  end
end
