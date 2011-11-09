require 'vindicia/xml_builder'

module Vindicia
  module SoapClient
    include XMLBuilder

    def find(id)
      self.send(:"fetch_by_merchant_#{underscore(name)}_id", id)
    end

    def method_missing(method, *args)
      # TODO: verify that this method _is_ a method callable on the wsdl,
      #       and defer to super if not.
      method = underscore(method.to_s).to_sym # back compatability from camelCase api
      if soap.wsdl.soap_actions.include? method
        define_method(method) {
          response = soap.request(:wsdl, method) do |soap, wsdl, http|
            http.auth.ssl.verify_mode = :none if Vindicia.environment == 'prodtest'
            soap.namespace["xmlns:vin"] = Vindicia.namespace
          end

          values = response.to_hash[:"#{method}_response"]
          return values
        }
=begin
        out_vars = nil # set up outside variable

        response = soap.request(:wsdl, method) do |soap, wsdl, http|
          # Don't care about broken SSL when testing
          http.auth.ssl.verify_mode = :none if Vindicia.environment == 'prodtest'

          out_vars = wsdl.arg_list["#{method.to_s.lower_camelcase}_out"]

          soap.namespaces["xmlns:vin"] = Vindicia.namespace
          soap.body = begin
            xml = Builder::XmlMarkup.new

            key = "#{method.to_s.lower_camelcase}_in"
            # WTF IS GOING ON HERE?
            results = wsdl.arg_list[key].zip([Vindicia.auth] + args)
            results.each do |arg, data|
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
=end
      else
        super
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
end
