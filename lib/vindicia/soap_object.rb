require 'vindicia/xml_builder'

module Vindicia
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

    def [](attr)
      key = camelcase(attr.to_s)
      Vindicia.coerce(key, attributes[key], instance_variable_get("@#{underscore(attr)}"))
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
        self[key]
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
        next result if name == 'attributes'
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
end
