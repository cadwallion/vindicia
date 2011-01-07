require 'vindicia'

require 'spec/authenticate'

describe Vindicia::Account do
  it 'should return a singleton soap wrapper' do
    a = Vindicia::Account
    b = Vindicia::Account
    a.wsdl.should be_equal(b.wsdl)
  end
  
  describe '#new' do
    it 'should handle nil' do
      Vindicia::Account.new.ref.should == {'merchantAccountId' => nil}
    end
    
    it 'should handle a string' do
      Vindicia::Account.new('thing').ref.should == {'merchantAccountId' => 'thing'}
    end
    
    it 'should handle a hash' do
      Vindicia::Account.new(:merchantAccountId => 'thing').ref.should == {'merchantAccountId' => 'thing'}
    end
  end
  
  describe '#update' do
    it 'should create/update an account' do
      account, created = Vindicia::Account.update({
        :merchantAccountId => "bob#{Time.now.to_i}",
        :name => "bob"
      })
      account.VID.should =~ /^[0-9a-f]{40}$/
    end
    
    it 'should accept raw objects' do
      account, created = Vindicia::Account.update(Vindicia::Account.new({
        :merchantAccountId => "bob#{Time.now.to_i}",
        :name => "long"
      }))
      account.name.should == "long"
      account.VID.should =~ /^[0-9a-f]{40}$/
    end

    it 'should update a name' do
      account, created = Vindicia::Account.update({
        :merchantAccountId => '123',
        :name => 'bob'
      })
      account.name.should == 'bob'

      account, created = Vindicia::Account.update({
        :merchantAccountId => '123',
        :name => 'sam'
      })
      account.name.should == 'sam'
    end
  end
  
  describe '#find' do
    it 'should return an account' do
      name = "bob#{Time.now.to_i}"
      Vindicia::Account.update({
        :merchantAccountId => '123',
        :name => name
      })
      account = Vindicia::Account.find('123')
      account.name.should == name
    end
  end
  
end

describe Vindicia::Product do
  it 'should look up by merchant id' do
    product = Vindicia::Product.find('em-2-PREMIUM-USD')
    product.description.should == 'Premium (49.0 USD)'
  end
  
  it 'should bundle the "Return" status in the Product' do
    product = Vindicia::Product.find('em-2-PREMIUM-USD')
    product.request_status.code.should == 200
  end
end

describe Vindicia do
  before :each do
    # Product, BillingPlan are set up in CashBox by hand
    account, created = Vindicia::Account.update({
      :merchantAccountId => Time.now.to_i.to_s,
      :name => "Integration User #{Time.now.to_i}"
    })
    @account, validated = Vindicia::Account.updatePaymentMethod(account.ref, {
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
    }, true, 'Validate', nil)
  end
  
  it 'should map payment method to a Vindicia:: class' do
    @account.paymentMethods.first.class.should == Vindicia::PaymentMethod
  end

  describe Vindicia::AutoBill do
    it 'should create recurring billing' do
      @product = Vindicia::Product.new('em-2-PREMIUM-USD')
      @billing = Vindicia::BillingPlan.new('em-2-PREMIUM-USD')
      autobill, created, authstatus, firstBillDate, firstBillAmount, firstBillingCurrency = \
      Vindicia::AutoBill.update({
        :account => @account.ref,
        :product => @product.ref,
        :billingPlan => @billing.ref
      }, 'Fail', true, 100)
    
      autobill.request_status.code.should == 200
    end
  end

  describe Vindicia::Transaction do
    describe '#auth' do
      it 'should auth a purchase' do
        payment_vid = @account.paymentMethods.first.VID
        transaction = Vindicia::Transaction.auth({
          :account                => @account.ref,
          :merchantTransactionId  => "Purchase.id (#{Time.now.to_i})",
          :sourcePaymentMethod    => {:VID => payment_vid},
          :amount                 => 49.00,
          :transactionItems       => [{:sku => 'sku', :name => 'Established Men Subscription', :price => 49.00, :quantity => 1}]
          #:divisionNumber                xsd:string
          #:userAgent                     xsd:string
          #:sourceMacAddress              xsd:string
          #:sourceIp                      xsd:string
          #:billingStatementIdentifier    xsd:string
        }, 100, false)
        transaction.request_status.code.should == 200
      end
    end

    describe '#capture' do
      before :each do
        payment_vid = @account.paymentMethods.first.VID
        @transaction = Vindicia::Transaction.auth({
          :account                => @account.ref,
          :merchantTransactionId  => "Purchase.id (#{Time.now.to_i})",
          :sourcePaymentMethod    => {:VID => payment_vid},
          :amount                 => 49.00,
          :transactionItems       => [{:sku => 'sku', :name => 'Established Men Subscription', :price => 49.00, :quantity => 1}]
        }, 100, false)
      end
      
      it 'should capture an authorized purchase' do
        ret, success, fail, results = Vindicia::Transaction.capture([@transaction.ref])
        success.should == 1
        results.first.merchantTransactionId.should == @transaction.merchantTransactionId
        results.first.returnCode.should == 200
        
        pending 'a way to force immediate capturing'
        transaction = Vindicia::Transaction.find(@transaction.merchantTransactionId)
        transaction.statusLog.first['status'].should == 'Captured'
      end
    end

    describe '#authCapture' do
      it 'should return a captured transaction' do
        payment_vid = @account.paymentMethods.first.VID
        transaction = Vindicia::Transaction.authCapture({
          :account                => @account.ref,
          :merchantTransactionId  => "Purchase.id (#{Time.now.to_i})",
          :sourcePaymentMethod    => {:VID => payment_vid},
          :amount                 => 49.00,
          :transactionItems       => [{:sku => 'sku', :name => 'Established Men Subscription', :price => 49.00, :quantity => 1}]
        }, false)
        pending 'a way to force immediate capturing'
        transaction.statusLog.first['status'].should == 'Captured'
      end
    end
  end
end
