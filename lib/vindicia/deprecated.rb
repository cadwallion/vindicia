require 'vindicia/deprecated/soap_object'
require 'vindicia/deprecated/xml_builder'
require 'vindicia/deprecated/soap_client'
require 'vindicia/deprecated/api_classes'
require 'vindicia/deprecated/data_types'

module Vindicia
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
    return value if value.kind_of? Vindicia::SoapObject

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

  def class(type)
    klass = type.split(':').last
    klass = singularize($1) if klass =~ /^ArrayOf(.*)$/
    Vindicia.const_get(klass) rescue nil
  end
  # customized data classes
  class Return < SoapObject
    def code; self.return_code.to_i; end
    def response; self.return_string; end
  end
end
