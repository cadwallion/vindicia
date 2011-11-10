require 'open-uri'
require 'net/http'
require 'vindicia'

module Vindicia
  module Bootstrap
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
      if valid_soap_api? Vindicia.wsdl(class_name)
        puts "Bootstrapping class #{class_name}"
        klass = const_set(class_name.to_sym, Class.new do
          def self.client                
            @client ||= Savon::Client.new do |wsdl|
              wsdl.endpoint = Vindicia.endpoint
            end  
          end

          def self.soap_call(method, args, endpoint = Vindicia.endpoint)
            return self.client.request(:wsdl, method) do
              http.auth.ssl.verify_mode = :none if Vindicia.environment == 'prodtest'
              wsdl.endpoint = endpoint

              soap.namespaces["xmlns:vin"] = Vindicia.namespace
              soap.namespaces["xmlns:tns"] = Vindicia.namespace
              soap.body = { :auth => Vindicia.auth }.merge(args)
            end
          end

        end)

        klass.client.wsdl.document = Vindicia.wsdl(class_name)

        klass.client.wsdl.soap_actions.each do |method|
          bootstrapped_method = bootstrap_method(method)
          klass.module_eval &bootstrapped_method
        end
      end
    end

    # Builds a Proc to define the method for a SOAP call
    # 
    # @param [Symbol] - method name to be bootstrapped
    # @return [Proc] - proc containing method definition to be eval'd
    def bootstrap_method method
      puts "Bootstrapping method #{method}"
      return proc do
        (class << self; self ; end).send :define_method, method do |*args|
          endpoints = [Vindicia.endpoint]

          if Vindicia.environment == 'production'
            endpoints << Vindicia.endpoint('fallback')
          end

          endpoints.each do |endpoint|
            response = self.soap_call(method, args.first, endpoint)

            if response.http_error?
              # @TODO: Log the failure and that we're moving to fallback
              next
            else
              return response
            end
          end
          raise Savon::HTTP::Error, 'All endpoints appear offline'
        end
      end
    end

    
    def valid_soap_api? wsdl_loc
      xsd_response = Net::HTTP.get_response(URI.parse(wsdl_loc)) 
      
      if xsd_response.code == '200'
        true
      else
        false
      end
    end
  end
end
