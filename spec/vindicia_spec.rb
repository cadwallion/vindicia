require 'spec_helper'

describe Vindicia::Account do
  it 'should return a singleton soap wrapper' do
    a = Vindicia::Account
    b = Vindicia::Account
    a.soap.should be_equal(b.soap)
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

    it 'should handle multiple words' do
      Vindicia::AutoBill.new(:merchantAutoBillId => 'thing').ref.should == {'merchantAutoBillId' => 'thing'}
    end

    it 'should handle underscored words' do
      Vindicia::AutoBill.new(:merchant_auto_bill_id => 'thing').ref.should == {'merchantAutoBillId' => 'thing'}
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

describe Vindicia::SoapObject do
  it 'should map associated classes' do
    product = Vindicia::Product.new(
      :default_billing_plan => {:status => "Active"}
    )
    product.default_billing_plan.should be_kind_of(Vindicia::BillingPlan)
  end

  it 'should allow hash access' do
    product = Vindicia::Product.new(
      :default_billing_plan => {:status => "Active"}
    )
    product['defaultBillingPlan'].should_not be_nil
    product['defaultBillingPlan'].should == product.default_billing_plan
  end

  it 'should deserialze arrays' do
    plan = Vindicia::BillingPlan.new(
      :periods => [{
        :quantity => "1"
      }]
    )
    plan.periods.should be_kind_of(Array)
    plan.periods.size.should == 1
    plan.periods.first.should be_kind_of(Vindicia::BillingPlanPeriod)
  end

  it 'should deserialize arrays from soap' do
    plan = Vindicia::BillingPlan.new(
      :status => "Active",
      :periods => {
        :periods => {
          :do_not_notify_first_bill => true,
          :prices => {
            :prices => {
              :type     => "namesp32:BillingPlanPrice",
              :xmlns    => "",
              :currency => "USD",
              :amount   => "49.00",
              :price_list_name => {:type=>"xsd:string", :xmlns=>""}
            },
            :type  => "namesp32:ArrayOfBillingPlanPrices",
            :xmlns => "",
            :array_type => "namesp32:BillingPlanPrice[1]"
          },
          :type => ["Month", "namesp32:BillingPlanPeriod"],
          :expire_warning_days => "0",
          :quantity => "1",
          :cycles => "0",
          :xmlns => ""
        },
        :type => "namesp32:ArrayOfBillingPlanPeriods",
        :xmlns => "",
        :array_type => "namesp32:BillingPlanPeriod[1]"
      }
    )

    plan.periods.should be_kind_of(Array)
    plan.periods.size.should == 1
    plan.periods.first.should be_kind_of(Vindicia::BillingPlanPeriod)
  end

  it 'should deserialize empty arrays from soap' do
    ret, transactions = Vindicia::Transaction.fetchDeltaSince(Date.new(2011,2,1), Date.new(2011,2,2), 500, 10, nil)

    ret.should be_kind_of(Vindicia::Return)
    transactions.should == []
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
  
  it 'should map associated objects to a Vindicia:: class' do
    @account.paymentMethods.first.class.should == Vindicia::PaymentMethod
  end

  it 'should map nil objects to nil' do
    @account.preferred_language.should be_nil
  end

  it 'should map associated arrays to a Vindicia:: class' do
    transaction = Vindicia::Transaction.auth({
      :account                => @account.ref,
      :merchantTransactionId  => "Purchase.id (#{Time.now.to_i})",
      :sourcePaymentMethod    => {:VID => @account.paymentMethods.first.VID},
      :amount                 => 49.00,
      :transactionItems       => [{:sku => 'sku', :name => 'Established Men Subscription', :price => 49.00, :quantity => 1}]
    }, 100, false)
    transaction.request_status.code.should == 200

    transaction.statusLog.first.should be_kind_of(Vindicia::TransactionStatus)
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

    it 'can adjust next billing date backwards' do
      @product = Vindicia::Product.new('em-2-PREMIUM-USD')
      @billing = Vindicia::BillingPlan.new('em-2-PREMIUM-USD')
      @id = "autobill-#{Time.now.to_i}"
      autobill, created, authstatus, firstBillDate, firstBillAmount, firstBillingCurrency = \
      Vindicia::AutoBill.update({
        :account => @account.ref,
        :product => @product.ref,
        :billingPlan => @billing.ref,
        :merchant_auto_bill_id => @id
      }, 'Fail', true, 100)

      ab = Vindicia::AutoBill.find(@id)
      original_date = ab.future_rebills.first.timestamp
      Vindicia::AutoBill.delay_billing_to_date(Vindicia::AutoBill.new(@id), original_date - 2)

      ab2 = Vindicia::AutoBill.find(@id)
      new_date = ab2.future_rebills.first.timestamp

      new_date.should == original_date - 2
    end

    it 'should find date-boxed autobill updates' do
      date = Date.new(2011,1,1)
      ret, autobills = Vindicia::AutoBill.fetchDeltaSince(date, 1, 5, date+1)
      ret.code.should == 200
      autobills.size.should == 5
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

      it 'should auth a purchase with payment method ID' do
        payment_id = @account.paymentMethods.first.merchant_payment_method_id
        transaction = Vindicia::Transaction.auth({
          :account                => @account.ref,
          :merchantTransactionId  => "Purchase.id (#{Time.now.to_i})",
          :sourcePaymentMethod    => {:merchant_payment_method_id => payment_id},
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
      
      it 'should look up authorization' do
        @transaction['merchantTransactionId'].should =~ /^Purchase.id /
        @transaction.merchantTransactionId.should    =~ /^Purchase.id /
        @transaction.merchant_transaction_id.should  =~ /^Purchase.id /
      end

      it 'should capture an authorized purchase' do
        ret, success, fail, results = Vindicia::Transaction.capture([@transaction.ref])
        success.should == 1
        results.first.merchantTransactionId.should == @transaction.merchantTransactionId
        results.first.returnCode.should == 200
        
        pending 'a way to force immediate capturing'
        transaction = Vindicia::Transaction.find(@transaction.merchantTransactionId)
        transaction.statusLog.status.should == 'Captured'
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
        transaction.request_status.code.should == 200

        pending 'a way to force immediate capturing'
        transaction.statusLog.status.should == 'Captured'
      end
    end
  end
end
