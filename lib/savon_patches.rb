class Savon::WSDL::Document
  def arg_list
    parser.arg_list
  end
end

class WSDLParserWithArgList < Savon::WSDL::Parser
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
    if tag == "message"
      @section_name = attrs["name"]
      @arg_list[@section_name] = []
    elsif tag == "part"
      @arg_list[@section_name] << attrs
    end
  end
end

module XSavon
  module WSDL
    class Parser
      # Hook method called when the stream parser encounters a starting tag.
      def tag_start(tag, attrs)
        # read xml namespaces if root element
        read_namespaces(attrs) if @path.empty?

        tag, namespace = tag.split(":").reverse
        @path << tag

        if @section == :binding && tag == "binding"
          # ensure that we are in an wsdl/soap namespace
          @section = nil unless @namespaces[namespace].starts_with? "http://schemas.xmlsoap.org/wsdl/soap"
        end

        @section = tag.to_sym if Sections.include?(tag) && depth <= 2

        @namespace ||= attrs["targetNamespace"] if @section == :definitions
        @endpoint ||= URI(URI.escape(attrs["location"])) if @section == :service && tag == "address"

        operation_from tag, attrs if @section == :binding && tag == "operation"
      end

      # Hook method called when the stream parser encounters a closing tag.
      def tag_end(tag)
        @path.pop

        if @section == :binding && @input && tag.strip_namespace == "operation"
          # no soapAction attribute found till now
          operation_from tag, "soapAction" => @input
        end
      end

      # Stores available operations from a given tag +name+ and +attrs+.
      def operation_from(tag, attrs)
        @input = attrs["name"] if attrs["name"]

        if attrs["soapAction"]
          @action = !attrs["soapAction"].blank? ? attrs["soapAction"] : @input
          @input = @action.split("/").last if !@input || @input.empty?

          @operations[@input.snakecase.to_sym] = { :action => @action, :input => @input }
          @input, @action = nil, nil
        end
      end
    end
  end
end
