require 'lib/vindicia'
require 'spec'

require 'spec/authenticate'

describe Vindicia::Account do
  before :each do
    @client = Vindicia::Account.new
  end

  it 'should return a singleton soap wrapper' do
    a = Vindicia::Account.new
    b = Vindicia::Account.new
    a.wsdl_.should be_equal(b.wsdl_)
  end
  
  describe '#update' do
    it 'should create/update an account' do
      ret, account, created = @client.update({
        :merchantAccountId => "123",
        :name => "bob"
      })
      account['VID'].should =~ /^[0-9a-f]{40}$/
    end

    it 'should update a name' do
      ret, account, created = @client.update({
        :merchantAccountId => '123',
        :name => 'bob'
      })
      account['name'].should == 'bob'

      ret, account, created = @client.update({
        :merchantAccountId => '123',
        :name => 'sam'
      })
      account['name'].should == 'sam'
    end
  end
  
  describe '#fetchByMerchantAccountId' do
    it 'should return an account' do
      @client.update({
        :merchantAccountId => '123',
        :name => 'bob'
      })
      ret, account = @client.fetchByMerchantAccountId('123')
      account['name'].should == 'bob'
    end
  end
  
end
