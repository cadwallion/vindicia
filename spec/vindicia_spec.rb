require 'spec_helper'

describe Vindicia do
  before do
    stub_wsdls
  end

  after do
    FakeWeb.clean_registry
  end

  describe "#authenticate" do
    it "should set authentication parameters" do
      Vindicia.authenticate('login', 'password', 'production')
      Vindicia.login.should == 'login'
      Vindicia.password.should == 'password'
      Vindicia.environment.should == 'production'
    end

    it "should default environment to prodtest" do
      Vindicia.authenticate('login', 'password')
      Vindicia.environment.should == 'prodtest'
    end
  end

  describe "#configure" do
    it "should yield Vindicia for configuration" do
      Vindicia.stub(:bootstrap) { }
      Vindicia.configure do |config|
        config.login = 'login'
      end
      Vindicia.login.should == 'login'
    end

    it "should trigger a bootstrap of the API after evaluation" do
      Vindicia.should_receive(:bootstrap) { }
      Vindicia.configure do |config|
        config.login = 'login'
      end
    end
  end

  describe "#domain" do
    context "no parameter passed" do
      it "should return a domain based on environment" do
        Vindicia.environment = 'staging'
        Vindicia.domain.should == 'soap.staging.sj.vindicia.com'
      end
    end
    
    context "environment parameter passed" do
      it "should return a domain based on parameter passed" do
        Vindicia.environment = 'staging'
        Vindicia.domain('fallback').should == 'soap-alt.vindicia.com'
      end
    end
  end

  describe "#wsdl" do
    it "should return the wsdl based on domain and class passed" do
      Vindicia.wsdl('Account').should == "http://#{Vindicia.domain}/#{Vindicia.version}/Account.wsdl"
    end
  end

  describe "#auth" do
    it "should return a hash of authentication" do
      Vindicia.authenticate('login', 'password')
      Vindicia.version = '3.6'
      Vindicia.auth.should == { 'login' => 'login', 'password' => 'password', 'version' => '3.6' }
    end
  end

  describe "#endpoint" do
    Vindicia.environment = 'prodtest'
    Vindicia.version = '3.7'
    Vindicia.endpoint.should == "https://soap.prodtest.sj.vindicia.com/v3.7/soap.pl"
  end
end

describe "Vindicia::Product" do
  before do
    Vindicia.configure do |config|
      config.environment = 'prodtest'
      config.version = '3.6'
    end
  end

  describe "#fetch_all" do
    it "should call Vindicia.parse_response" do
      Vindicia.should_receive(:parse_response)
      Vindicia::Product.fetch_all(:page => 1, :pageSize => 2)
    end

    context "in production when primary endpoint fails" do
      before do
        Vindicia.environment = 'production'
      end

      it "should retry the API call on the fallback endpoint" do
        FakeWeb.register_uri(:get, "https://soap.vindicia.com/v3.6/soap.pl",
                           :status => ['500', 'Unexpected error'])

        FakeWeb.register_uri(:get, "https://soap-alt.vindicia.com/v3.6/soap.pl",
                          :body => File.read(File.dirname(__FILE__) + "/support/fetch_all.xml"))

        Vindicia.stub(:parse_response) { }
        Vindicia::Product.should_receive(:soap_call).exactly(2).times
        Vindicia::Product.fetch_all(:page => 1, :pageSize => 2)
      end
    end
  end
end
