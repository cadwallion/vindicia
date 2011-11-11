require 'ostruct'

module Vindicia
  class Parser
    attr_reader :soap_response, :method_called, :xml_response
    attr_accessor :parsed_response
    def initialize(soap_response, method_called)
      @soap_response = soap_response
      @xml_response = Crack::XML.parse(soap_response.to_xml)
      @method_called = method_called
    end

    def parse
      hash = @xml_response.find_soap_body["#{@method_called}_response".to_sym]
      if Vindicia.objectify?
        return objectify(hash) { |k,v| k == :xmlns }
      else
        return hash
      end
    end

    # Takes a data representation (in this case SOAP XML) and recursively converts to
    # an OpenStruct object system
    #
    # @param [Hash,Array] The current context to be converted.
    # @param &block to be used for filtration of hash keys. Optional
    # @return the objectified result, minus any filtered keys
    def objectify(current_context, &block)
      case current_context
      when Array
        context_array = []
        current_context.each do |elem|
          context_array << objectify(elem, &block)
        end
        return context_array
      when Hash
        object = OpenStruct.new
        if block_given?
          temp_hash = current_context.reject &block
        else
          temp_hash = current_context.dup
        end

        temp_hash.each_key do |key|
          object.send "#{key}=".to_sym, objectify(temp_hash[key], &block)
        end
        return object
      else
        return current_context
      end
    end
  end
end
