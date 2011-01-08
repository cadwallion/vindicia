class Savon::SOAP::XML
  def self.to_hash(xml)
    # Vindicia xml isn't _completely_ self-documenting. Ensure xsi header exists.
    if xml =~ /soap.vindicia.com/ and xml !~ /xmlns:xsi/
      xml = xml.sub(/soap:Envelope/, "soap:Envelope\n    xmlns:xsi=\"#{SchemaTypes["xmlns:xsi"]}\"")
    end
    (Crack::XML.parse(xml) rescue {}).find_soap_body
  end
end

class Savon::WSDL::Document
  def arg_list
    # simple passthrough
    parser.arg_list
  end
end

class Savon::WSDL::ParserWithArgList < Savon::WSDL::Parser
  attr_reader :arg_list
  
  def initialize
    super
    @arg_list = {}
  end
  
  def tag_start(tag, attrs)
    super
    arg_list_from tag, attrs if @section == :message
  end
  
  def arg_list_from(tag, attrs)
    # Track argument lists so I can use arrays instead of hashes when posting data
    if tag == "message"
      @section_name = attrs["name"]
      @arg_list[@section_name] = []
    elsif tag == "part"
      @arg_list[@section_name] << attrs
    end
  end
end
