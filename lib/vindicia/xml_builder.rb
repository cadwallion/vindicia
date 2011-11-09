module Vindicia
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
        # format dates/times with full timestamp
        value = value.to_time.iso8601 if value.respond_to?(:to_time) && type == 'xsd:dateTime'
        xml.tag!(name, value, {"xsi:type" => type})
      end
    end
  end
end
