require 'spec_helper'

describe Vindicia::Bootstrap do
  def stub_bootstrap_method
    thing = proc do
      (class << self; self ; end).send :define_method, "foo" do |*args|
        # stub
      end
    end
    Vindicia.stub(:bootstrap_method) { thing }
  end

  before do
    Vindicia.set_bootstrapped(false)
  end

  describe "#bootstrap" do
    def mock_xml
      fake_xpath = double()
      fake_xpath.stub(:xpath) { [] }

      Nokogiri.should_receive(:XML) { fake_xpath }     
    end


    it "should retrieve an XSD to parse for APIs" do
      mock_xml
      Vindicia.bootstrap
    end

    it "should immediately return false if already bootstrapped" do
      Vindicia.set_bootstrapped
      Vindicia.should_not_receive(:bootstrap_class)
      Vindicia.bootstrap.should_not be_true
    end

    it "should set bootstrapped to true upon completion" do
      mock_xml
      Vindicia.bootstrap
      Vindicia.bootstrapped?.should be_true
    end

    it "should call bootstrap_class for each attribute in the parsed XSD" do
      Vindicia.environment = 'prodtest'
      Vindicia.version = '3.6'

      doc = Nokogiri::XML(open("http://#{Vindicia.domain}/#{Vindicia.version}/Vindicia.xsd"))
      classes = doc.xpath('//xsd:complexType').map { |e| e['name'] }

      Vindicia.should_receive(:bootstrap_class).exactly(classes.size).times
      Vindicia.bootstrap
    end
  end

  describe "#bootstrap_class" do
    after do
      Vindicia.class_eval do
        remove_const(:Account)
      end
    end
    let(:methods) { [:fetch_by_email, :fetch_by_merchant_account_id, :fetch_by_payment_method] }

    it "should define a class of type class_name" do
      Vindicia.stub(:valid_soap_api?) { true } 
      Vindicia.bootstrap_class("Account")
      Vindicia::Account.should respond_to(:class)
    end 

    it "should bootstrap its associated methods" do
      Vindicia.version = '3.6'
      Vindicia.stub(:valid_soap_api?) { true } 

      Vindicia.bootstrap_class("Account")
      methods.each do |method|
        Vindicia::Account.should respond_to(method)
      end
    end

    it "should setup soap_call method on class" do
      Vindicia.stub(:valid_soap_api?) { true } 

      stub_bootstrap_method
      Vindicia.bootstrap_class("Account")
      Vindicia::Account.should respond_to(:soap_call)
    end
  end 

  describe "#bootstrap_method" do
    it "should return a Proc to be module_eval'd" do
      Vindicia.bootstrap_method("foo").should be_kind_of(Proc)
    end
    context "the returned Proc" do
      it "should define the method passed as the parameter" do
        definition = Vindicia.bootstrap_method("foo")
        class DummyClass ; end
        DummyClass.module_eval &definition
        DummyClass.should respond_to(:foo)
        Object.send :remove_const, :DummyClass
      end

    end
  end

  describe "#clear_api_cache" do
    it "should undefine all the Vindicia constants" do
      Vindicia.version = '3.6'
      Vindicia.stub(:valid_soap_api?) { true } 
      Vindicia.bootstrap_class("Account")

      Vindicia.clear_api_cache

      Vindicia.constants.should_not include(:Account)
    end

    it "should reset bootstrapped state" do
      Vindicia.set_bootstrapped(true)
      Vindicia.clear_api_cache
      Vindicia.bootstrapped?.should_not be_true
    end
  end
end
