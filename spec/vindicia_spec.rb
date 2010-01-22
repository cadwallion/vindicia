require 'lib/vindicia'
require 'spec'

require 'spec/authenticate'

describe Vindicia::Account do
  before :each do
    @client = Vindicia::Account
  end

  it 'should return a singleton soap wrapper' do
    a = Vindicia::Account
    b = Vindicia::Account
    a.wsdl.should be_equal(b.wsdl)
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

describe Vindicia do
  it 'should set up a recurring purchase' do
    # Product, BillingPlan are set up in CashBox by hand
    ret, account, created = Vindicia::Account.update({
      :merchantAccountId => Time.now.to_i.to_s,
      :name => 'Integration User'
    })
    ret, account, validated = Vindicia::Account.updatePaymentMethod({
      # Account
      :VID => account['VID'],
      :emailTypePreference => 'plaintext'
    }, {
      # Payment Method
      :type => 'CreditCard',
      :creditCard => {
        :account => '4783684405207461',
        :expirationDate => '201207',
        :hashType => 'sha1'
      },
      :accountHolderName => 'John Smith',
      :billingAddress => {
        :name => 'John Smith',
        :addr1 => '123 Main St',
        :city => 'Toronto',
        :district => 'Ontario',
        :country => 'Canada',
        :postalCode => 'M4V 5X7'
      },
      :merchantPaymentMethodId => "Purchase.id #{Time.now.to_i}"
    }, true, 'Update', nil)
    ret, product = Vindicia::Product.fetchByMerchantProductId('em-2-PREMIUM-USD')
    ret, billing = Vindicia::BillingPlan.fetchByMerchantBillingPlanId('em-2-PREMIUM-USD')
    ret, autobill, created, authstatus, firstBillDate, firstBillAmount, firstBillingCurrency =
      Vindicia::AutoBill.update({
        :account => {:VID => account['VID'], :emailTypePreference => 'plaintext'},
        :product => {:VID => product['VID'], :status => product['status'], :taxClassification => product['taxClassification']},
        :billingPlan => {:VID => billing['VID'], :status => billing['status']},
        :status => 'Active'
      }, 'Fail', true, 100)
  end
end

