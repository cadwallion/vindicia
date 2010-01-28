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
      account, created = @client.update({
        :merchantAccountId => "123",
        :name => "bob"
      })
      account.VID.should =~ /^[0-9a-f]{40}$/
    end

    it 'should update a name' do
      account, created = @client.update({
        :merchantAccountId => '123',
        :name => 'bob'
      })
      account.name.should == 'bob'

      account, created = @client.update({
        :merchantAccountId => '123',
        :name => 'sam'
      })
      account.name.should == 'sam'
    end
  end
  
  describe '#find_by_merchant_id' do
    it 'should return an account' do
      @client.update({
        :merchantAccountId => '123',
        :name => 'bob'
      })
      account = @client.find_by_merchant_id('123')
      account.name.should == 'bob'
    end
  end
  
end

describe Vindicia::Product do
  it 'should look up by merchant id' do
    product = Vindicia::Product.find_by_merchant_id('em-2-PREMIUM-USD')
    product.description.should == 'EM PREMIUM-USD Subscription'
  end
  
  it 'should look up by VID' do
    product = Vindicia::Product.find_by_vid('3ef764ca203485052c99db99401c0f5a1e9c03d4')
    product.description.should == 'EM PREMIUM-USD Subscription'
  end
  
  it 'should bundle the "Return" status in the Product' do
    product = Vindicia::Product.find_by_merchant_id('em-2-PREMIUM-USD')
    product.request_status.code.should == 200
  end
end

describe Vindicia do
  it 'should set up a recurring purchase' do
    # Product, BillingPlan are set up in CashBox by hand
    account, created = Vindicia::Account.update({
      :merchantAccountId => Time.now.to_i.to_s,
      :name => 'Integration User'
    })
    account, validated = Vindicia::Account.updatePaymentMethod(account.vid_reference, {
      # Payment Method
      :type => 'CreditCard',
      :creditCard => {
        :account => '4783684405207461',
        :expirationDate => '201207'
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
    })
    product = Vindicia::Product.find_by_merchant_id('em-2-PREMIUM-USD')
    billing = Vindicia::BillingPlan.find_by_merchant_id('em-2-PREMIUM-USD')
    autobill, created, authstatus, firstBillDate, firstBillAmount, firstBillingCurrency = \
    Vindicia::AutoBill.update({
      :account => account.vid_reference,
      :product => product.vid_reference,
      :billingPlan => billing.vid_reference
    })
    
    autobill.request_status.code.should == 200
  end
end

