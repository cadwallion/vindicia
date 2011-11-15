require 'open-uri'
require 'net/http'
require 'vindicia'

module Vindicia
  module Bootstrap
    module ClassMethods
      def client                
        @client ||= Savon::Client.new do |wsdl|
          wsdl.endpoint = Vindicia.endpoint
        end  
      end

      def soap_call(method, args, endpoint = Vindicia.endpoint)
        return self.client.request(:wsdl, method) do
          http.auth.ssl.verify_mode = :none if Vindicia.environment == 'prodtest'
          wsdl.endpoint = endpoint

          soap.namespaces["xmlns:vin"] = Vindicia.namespace
          soap.namespaces["xmlns:tns"] = Vindicia.namespace
          soap.body = { :auth => Vindicia.auth }.merge(args)
        end
      end
    end

    # Pulls a .XSD that maps every SOAP API in the system, and delegates to 
    # bootstrap each class
    def bootstrap
      return false if bootstrapped?
      doc = Nokogiri::XML(open("http://#{domain}/#{version}/Vindicia.xsd"))
      classes = doc.xpath('//xsd:complexType').map { |e| e['name'] }
      classes.each do |class_name|
        bootstrap_class(class_name)
      end
      @bootstrapped = true
    end

    # forces a bootstrap regardless of previous state
    def bootstrap!
      @bootstrapped = false
      bootstrap
    end

    # :nodoc:
    def bootstrapped?
      @bootstrapped ||= false
    end

    # Dynamically generates a class for each WSDL, then delegates to generate
    # the soap_actions as methods
    # 
    # @param [String] - class name that maps to Vindicia SOAP APIs
    # @return Class - class defined
    def bootstrap_class(class_name)
      if valid_soap_api? class_name
        klass = const_set(class_name.to_sym, Class.new do
          extend Vindicia::Bootstrap::ClassMethods
        end)

        klass.client.wsdl.document = determine_wsdl(class_name)

        klass.client.wsdl.soap_actions.each do |method|
          bootstrapped_method = bootstrap_method(method)
          klass.module_eval &bootstrapped_method
        end
      end
    end

    def determine_wsdl class_name
      local_path = File.dirname(__FILE__)+"/api-cache/#{Vindicia.version}/#{class_name}.wsdl"
      if File.exists? local_path
        return local_path
      else
        Vindicia.wsdl(class_name)
      end
    end

    # Builds a Proc to define the method for a SOAP call
    # 
    # @param [Symbol] - method name to be bootstrapped
    # @return [Proc] - proc containing method definition to be eval'd
    def bootstrap_method method
      return proc do
        (class << self; self ; end).send :define_method, method do |*args|
          endpoints = [Vindicia.endpoint]

          if Vindicia.environment == 'production'
            endpoints << Vindicia.endpoint('fallback')
          end

          endpoints.each do |endpoint|
            response = self.soap_call(method, args.first, endpoint)

            if response.nil?
              next
            elsif response.http_error?
              next
            else
              return Vindicia.parse_response(response, method)
            end
          end
        end
      end
    end

    
    def valid_soap_api? class_name
      wsdl = determine_wsdl(class_name)
      if File.exists? wsdl
        return true
      else
        xsd_response = Net::HTTP.get_response(URI.parse(wsdl)) 
        
        if xsd_response.code == '200'
          cache_wsdl(class_name, xsd_response.body)
          true
        else
          false
        end
      end
    end

    def cache_wsdl class_name, wsdl_body
      cache_path = "#{File.dirname(__FILE__)}/api-cache/#{Vindicia.version}"
      FileUtils.mkdir_p cache_path
      File.open("#{cache_path}/#{class_name}.wsdl", "w+") do |file|
        file << wsdl_body
      end
    end
  end
end
