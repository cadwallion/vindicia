require 'spec_helper'

describe Vindicia::Parser do

  before do
    @soap_response = double()
    # TODO: Setup VCR
    contents = File.read(File.dirname(__FILE__) + "/support/fetch_all.xml")
    @soap_response.stub(:to_xml) { contents }
    @parser = Vindicia::Parser.new @soap_response, "fetch_all"
  end

  describe "#parse" do
    context "Vindicia.objectify is false" do
      before do
        Vindicia.objectify = false
      end
      it "should return a hash of the responses" do
        @parser.parse.should be_kind_of(Hash)
      end
    end
    
    context "Vindicia.objectify is true" do
      before do
        Vindicia.objectify = true
      end

      it "should return an OpenStruct mapping of the SOAP response" do
        @parser.parse.should be_kind_of(OpenStruct)
      end
      
      it "should call Vindicia::Parser#objectify" do
        @parser.should_receive(:objectify)
        @parser.parse
      end
    end
  end

  describe "#objectify" do
    let(:test_hash) {
      {
        :foo => [
          "one",
          {
            :a => "f2a",
            :b => "f2b",
            :xmlns => "this should not exist"
          },
          3
        ]
      }
    }

    it "should return an OpenStruct mapping of the SOAP response" do
      response = @parser.objectify(test_hash) { |k,v| k == :xmlns }  
      response.foo[1].a.should == "f2a"
    end

    it "should reject the test conditions passed as a block" do
      response = @parser.objectify(test_hash) { |k,v| k == :xmlns }  
      response.foo[1].should_not respond_to(:xmlns)
    end
  end
end
