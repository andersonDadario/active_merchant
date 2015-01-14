require 'digest'
require 'base64'
require 'json'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MondidoGateway < Gateway
      self.display_name = 'Mondido'
      self.homepage_url = 'https://www.mondido.com/'
      self.live_url = 'https://api.mondido.com/v1/'

      # For the entire accepted currencies list from Mondido, please access:
      # http://doc.mondido.com/api#currencies
      self.default_currency = 'USD'

      # :dollars  => decimal (e.g., 10.00)
      # :cents    => integer with cents (e.g., 1000 = $10.00)
      self.money_format = :dollars

      # Need to confirm if there is more ...
      self.supported_countries = %w(SE)

=begin
      [ FROM MONDIDO DOCS ]
      Supported Card Types

      Default card types that you will have access to are VISA and Mastercard,
      but the other such as AMEX, JCB and Diners are on separate contracts.
      Contact support for more information about card types.

      visa (Visa)
      mastercard (MasterCard)
      maestro (Maestro)
      electron (Electron)
      debit_mastercard (Debit MasterCard)
      visa_debit (Visa Debit)
      laser (Laser)
      solo (Solo)
      amex (American Express)
      diners (Diners)
      uk_maestro (UK Maestro)
      jcb (JCB)
      ukash_neo (Ukash NEO)
      discover (Discover)
      stored_card (Stored Card)

      [ FROM ACTIVE MERCHANT DOCS ]
      Credit Card Types

      :visa – Visa
      :master – MasterCard
      :discover – Discover Card
      :american_express – American Express
      :diners_club – Diners Club
      :jcb – JCB
      :switch – UK Maestro, formerly Switch
      :solo – Solo
      :dankort – Dankort
      :maestro – International Maestro
      :forbrugsforeningen – Forbrugsforeningen
      :laser – Laser
=end
      self.supported_cardtypes = [:visa, :master, :discover, :american_express, 
          :diners_club, :jcb, :switch, :solo, :maestro, :laser]

      # Not implemented
      CVC_CODE_TRANSLATOR = {
        '124' => 'S', # CVV should have been present
        '125' => 'N', # CVV does not match
=begin
        # Other Codes
        '' => 'D', # CVV check flagged transaction as suspicious
        '' => 'I', # CVV failed data validation check
        '' => 'M', # CVV matches
        '' => 'P', # CVV not processed
        '' => 'U', # CVV request unable to be processed by issuer
        '' => 'X'  # CVV check not supported for card
=end
      }

      # Mapping of error codes from Mondido to Gateway class standard error codes
      STANDARD_ERROR_CODE_TRANSLATOR = {
        'errors.card_number.missing' => STANDARD_ERROR_CODE[:invalid_number],
        'errors.card_number.invalid' => STANDARD_ERROR_CODE[:invalid_number],
        'errors.card_expiry.missing' => STANDARD_ERROR_CODE[:invalid_expiry_date],
        'errors.card_expiry.invalid' => STANDARD_ERROR_CODE[:invalid_expiry_date],
        'errors.card_cvv.missing' => STANDARD_ERROR_CODE[:invalid_cvc],
        'errors.card_cvv.invalid' => STANDARD_ERROR_CODE[:invalid_cvc],
        'errors.card.expired' => STANDARD_ERROR_CODE[:expired_card],
        'errors.zip.missing' => STANDARD_ERROR_CODE[:incorrect_zip],
        'errors.address.missing' => STANDARD_ERROR_CODE[:incorrect_address],
        'errors.city.missing' => STANDARD_ERROR_CODE[:incorrect_address],
        'errors.country_code.missing' => STANDARD_ERROR_CODE[:incorrect_address],
        'errors.payment.declined' => STANDARD_ERROR_CODE[:card_declined],
        'errors.unexpected' => STANDARD_ERROR_CODE[:processing_error]
      }

      def initialize(options={})
        requires!(options, :merchant_id, :api_token, :hash_secret)

        @merchant_id = options[:merchant_id]
        @api_token = options[:api_token]
        @hash_secret = options[:hash_secret]

        super
      end

      def purchase(money, payment, options={})
        # This is combined Authorize and Capture in one transaction. Sometimes we just want to take a payment!
        # API reference: http://doc.mondido.com/api#transaction-create

        options[:process] = true
        create_post_for_auth_or_purchase(money, payment, options)
      end

      def authorize(money, payment, options={})
        # Validate the credit card and reserve the money for later collection

        options[:process] = false
        create_post_for_auth_or_purchase(money, payment, options)
      end

      def capture(money, authorization, options={})
        # References a previous “Authorize” and requests that the money be drawn down.
        # It’s good practice (required) in many juristictions not to take a payment from a
        #   customer until the goods are shipped.
        # not implemented
      end

      def refund(money, authorization, options={})
        # Refund money to a card.
        # This may need to be specifically enabled on your account and may not be supported by all gateways
        requires!(options, :transaction_id, :amount, :reason)

        post = {
          # transaction_id  int *required
          #   ID for the transaction to refund
          :transaction_id => options[:transaction_id],

          # amount decimal *required 
          #   The amount to refund. Ex. 5.00
          :amount => options[:amount],

          # reason string *required
          #   The reason for the refund. Ex. "Cancelled order"
          :reason => options[:reason]

        }

        commit(:post, 'refunds', post)
      end

      def void(authorization, options={})
        # Entirely void a transaction.
        # not implemented
      end

      def verify(credit_card, options={})
        # not implemented

        #MultiResponse.run(:use_first_response) do |r|
        #  r.process { authorize(100, credit_card, options) }
        #  r.process(:ignore_result) { void(r.authorization, options) }
        #end
      end

      def store(payment, options = {})
        requires!(options, :customer_id)

        post = {
          # currency  string* required
          :currency => self.default_currency,

          # customer_ref  string
          #   Merchant specific customer ID.
          #   If this customer exists the card will be added to that customer.
          #   If it doesn't exists a customer will be created.
          :customer_ref => options[:customer_ref].to_s,

          # customer_id int
          #   Merchant specific customer ID.
          #   If this customer exists the card will be added to that customer.
          #   If it doesn't exists a customer will be created.
          :customer_id => options[:customer_id],

          # encrypted (string)
          #   A comma separated string for the params that you send encrypted.
          #   Ex. "card_number,card_cvv"
          :encrypted => '',

          # test bool
          #   Must be true if you are using a test card number.
          :test => test?

        }

        add_credit_card(post, payment)
        commit(:post, 'stored_cards', post)
      end

      def unstore(id)
        commit(:delete, "stored_cards/#{id}")
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((Authorization: Basic )\w+), '\1[FILTERED]').
          gsub(%r((card_holder=)\w+), '\1[FILTERED]').
          gsub(%r((card_cvv=)\d+), '\1[FILTERED]').
          gsub(%r((card_expiry=)\w+), '\1[FILTERED]').
          gsub(%r((card_number=)\d+), '\1[FILTERED]').
          gsub(%r((card_type=)\w+), '\1[FILTERED]').
          gsub(%r((hash=)\w+), '\1[FILTERED]').
          gsub(%r((amount=)\w+), '\1[FILTERED]')
      end

      private

      def create_post_for_auth_or_purchase(money, payment, options={})    
        # A complete (original) options hash might be:
        # options = {
        #   :order_id => '1',
        #   :ip => '10.0.0.1',
        #   :customer => 'Cody Fauser',
        #   :invoice => 525,
        #   :merchant => 'Test Ecommerce',
        #   :description => '200 Web 2.0 M&Ms',
        #   :email => 'codyfauser@gmail.com',
        #   :currency => 'usd',
        #   :address => {
        #     :name => 'Cody Fauser',
        #     :company => '',
        #     :address1 => '',
        #     :address2 => '',
        #     :city => '',
        #     :state => '',
        #     :country => '',
        #     :zip => '90210',
        #     :phone => ''
        #   }
        # }
        ## There are 3 different addresses you can use.
        ## There are :billing_address, :shipping_address, or you can just pass in
        ## :address and it will be used for both.

        ## Options Specific for Mondido Gateway - documentation below
        #  :process
        #  :metadata
        #  :plan_id
        #  :customer_ref
        #  :webhook

        requires!(options, :order_id)
        options[:order_id] = options[:order_id].to_s

        post = {
          # decimal* required
          # The transaction amount ex. 12.00
          :amount => get_amount(money, options),

          # string* required
          # Merchant order/payment ID
          :payment_ref => options[:order_id],

          # string* required
          # The currency (SEK, CAD, CNY, COP, CZK, DKK, HKD, HUF, ISK, INR, ILS, JPY, KES, KRW,
          #  KWD, LVL, MYR, MXN, MAD, OMR, NZD, NOK, PAB, QAR, RUB, SAR, SGD, ZAR, CHF, THB, TTD,
          #  AED, GBP, USD, TWD, VEF, RON, TRY, EUR, UAH, PLN, BRL)
          :currency => get_currency(money, options),

          # string * required
          # The hash is a MD5 encoded string with some of your merchant and order specific parameters,
          # which is used to verify the payment, and make sure that it is not altered in any way.
          :hash => transaction_hash_for(money, options)
        }

        ## API Optional Parameters
        #
        # - test
        # - process
        # - metadata
        # - plan id
        # - customer_ref
        # - webhook

        # test (boolean)
        #   Whether the transaction is a test transaction. Defaults false
        post[:test] = test?

        # process (bolean)
        #   Should be false if you want to process the payment at a later stage.
        #   You will not need to send in card data (card_number, card_cvv, card_holder, card_expiry) in this case.
        post[:process] = options[:process]

        # Merchant custom Metadata (string)
        #   Metadata is custom schemaless information that you can choose to send in to Mondido.
        #   It can be information about the customer, the product or about campaigns or offers.
        #
        #   The metadata can be used to customize your hosted payment window or sending personalized
        #   receipts to your customers in a webhook.
        #
        #   Details: http://doc.mondido.com/api#metadata
        post.merge!( :metadata => options[:metadata] ) if options[:metadata]

        # Plan ID (int)
        #   The ID of the subscription plan.
        post.merge!( :plan_id => options[:plan_id] ) if options[:plan_id]

        # customer_ref (string)
        #   The merchant specific user/customer ID
        post.merge!( :customer_ref => options[:customer_ref].to_s ) if options[:customer_ref]

        # webhook (object)
        #   You can specify a custom Webhook for a transaction.
        #   For example sending e-mail or POST to your backend.
        #   Details: http://doc.mondido.com/api#webhook
        post.merge!( :webhook => options[:webhook] ) if options[:webhook]


        add_credit_card(post, payment)
        #add_address(post, payment, options)
        #add_customer_data(post, options)
        commit(:post, 'transactions', post)
      end

      def transaction_hash_for(money, options={})
        # Hash recipe: MD5(merchant_id + payment_ref + customer_ref + amount + currency + test + secret)
        # Important to know about the hash-attributes
        # (1)  merchant_id (integer): your merchant id
        # (2)  payment_ref (string): a generated unique order id from your web shop
        # (3)  customer_ref (string): A unique id for your customer
        # (4)  amount (string): Must include two digits, example 10.00
        # (5)  currency (string): An ISO 4214 currency code, must be in lower case (ex. eur)
        # (6)  test (string): "test" if transaction is in test mode, otherwise empty string ""
        # (7)  secret (string): Unique merchant specific string

        hash_attributes = @merchant_id.to_s                                 # 1
        hash_attributes += options[:order_id]                               # 2
        hash_attributes += options[:customer_ref].to_s || ""                # 3
        hash_attributes += get_amount(money, options)                       # 4
        hash_attributes += get_currency(money, options)                     # 5
        hash_attributes += ((test?) ? "test" : "")                          # 6
        hash_attributes += @hash_secret                                     # 7

        md5 = Digest::MD5.new
        md5.update hash_attributes

        return md5.hexdigest
      end


      def add_customer_data(post, options)
        # Not implemented yet
      end

      def add_address(post, creditcard, options)
        # Not implemented yet
      end

      def add_credit_card(post, credit_card)
        post[:card_holder] = credit_card.name if credit_card.name
        post[:card_cvv] = credit_card.verification_value if credit_card.verification_value?
        post[:card_expiry] = format(credit_card.month, :two_digits) + format(credit_card.year, :two_digits)
        post[:card_number] = credit_card.number

        # Stored card variables
        # card_number => card_hash
        # card_type   => 'stored_card'
        if credit_card.respond_to?(:brand)
          post[:card_type] = credit_card.brand
        else
          post[:card_type] = ActiveMerchant::Billing::CreditCard.brand?(credit_card.number)
        end
      end

      def get_amount(money, options)
        currency = get_currency(money, options)
        localized_amount(money, currency)
      end

      def get_currency(money, options)
        (options[:currency] || currency(money)).downcase
      end  

      def commit(method, uri, parameters = nil, options = {})
        response = api_request(method, uri, parameters, options)
        success = (response["status"] == "approved")

        # Mondido doesn't check the purchase address vs billing address
        # So we use the standard code 'E'.
        # 'E' => AVS data is invalid or AVS is not allowed for this card type.
        # For more codes, please see the AVSResult class
        avs_code = 'E'

        # By default, we understand that the CVV matched (code "M")
        # But we find the error 124 or 125, we report the
        # related CVC Code to Active Merchant gem
        # 124: errors.card_cvv.missing
        # 125: errors.card_cvv.invalid
        cvc_code = "M"
        if not success? and ["124","125"].include? response["code"]
          cvc_code = CVC_CODE_TRANSLATOR[ response["code"] ]
        end

        Response.new(
          success,
          (success ? "Transaction approved" : response["description"]),
          response,
          test: response["test"],
          authorization: success ? response["id"] : response["description"],
          :avs_result => { :code => avs_code },
          :cvv_result => cvc_code,
          :error_code => success ? nil : STANDARD_ERROR_CODE_TRANSLATOR[response["name"]]
        )
      end

      def api_request(method, uri, parameters = nil, options = {})
        raw_response = response = nil
        begin
          raw_response = ssl_request(
            method,
            self.live_url + uri,
            post_data(parameters),
            headers(options)
          )

          response = parse(raw_response)
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end

        response
      end

      def post_data(params)
        return nil unless params

        params.map do |key, value|
          next if value.blank?
          if value.is_a?(Hash)
            h = {}
            value.each do |k, v|
              h["#{key}[#{k}]"] = v unless v.blank?
            end
            post_data(h)
          elsif value.is_a?(Array)
            value.map { |v| "#{key}[]=#{CGI.escape(v.to_s)}" }.join("&")
          else
            "#{key}=#{CGI.escape(value.to_s)}"
          end
        end.compact.join("&")
      end

      def headers(options = {})
        {
          "Authorization" => "Basic " + Base64.encode64("#{@merchant_id}:#{@api_token}").strip,
          "User-Agent" => "Mondido ActiveMerchantBindings/#{ActiveMerchant::VERSION}",
          #"X-Mondido-Client-User-Agent" => user_agent, # defined in Gateway.rb
          #"X-Mondido-Client-IP" => options[:ip] if options[:ip]
        }
      end

      def parse(body)
        JSON.parse(body)
      end

      def response_error(raw_response)
        begin
          parse(raw_response)
        rescue JSON::ParserError
          json_error(raw_response)
        end
      end

      def json_error(raw_response)
        msg = "Invalid response received from the Mondido API.\n"
        msg += "  Please contact support@mondido.com if you continue to receive this message.\n"
        msg += "  (The raw response returned by the API was #{raw_response.inspect})"

        {
          "error" => {
            "description" => msg
          }
        }
      end

    end
  end
end
