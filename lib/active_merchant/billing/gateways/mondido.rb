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

      # Need to confirm is there is more ...
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

      =========================================
      Questions:

      (1) Is Diner == DinerClub? In doubt I removed from supported_cardtypes
      (2) What about the card "ukash_neo"?
          It isn't supported in this gem. Need to suggest a pull request.

      (3) Is Electron == Visa Electron? In doubt I removed from supported_cardtypes
      (4) Is Visa && Visa Debit represented by :visa?
      (5) Is MasterCard && Debit MasterCard represented by :master?
=end
      self.supported_cardtypes = [:visa, :master, :discover, :american_express, :jcb,
       :switch, :solo, :maestro, :laser]


      # Not implemented
      AVS_CODE_TRANSLATOR = {
        '1' => 'A',  # Street address matches, but 5-digit and 9-digit postal code do not match.
        '2' => 'B',  # Street address matches, but postal code not verified.
        '3' => 'C',  # Street address and postal code do not match.
        '4' => 'D',  # Street address and postal code match.
        '5' => 'E',  # AVS data is invalid or AVS is not allowed for this card type.
        '6' => 'F',  # Card member's name does not match, but billing postal code matches.
        '7' => 'G',  # Non-U.S. issuing bank does not support AVS.
        '8' => 'H',  # Card member's name does not match. Street address and postal code match.
        '9' => 'I',  # Address not verified.
        '10' => 'J', # Card member's name, billing address, and postal code match. Shipping information verified
                     #     and chargeback protection guaranteed through the Fraud Protection Program.
        '11' => 'K', # Card member's name matches but billing address and billing postal code do not match.
        '12' => 'L', # Card member's name and billing postal code match, but billing address does not match.
        '13' => 'M', # Street address and postal code match.
        '14' => 'N', # Street address and postal code do not match.
        '15' => 'O', # Card member's name and billing address match, but billing postal code does not match.
        '16' => 'P', # Postal code matches, but street address not verified.
        '17' => 'Q', # Card member's name, billing address, and postal code match. Shipping information verified
                     #     but chargeback protection not guaranteed.
        '18' => 'R', # System unavailable.
        '19' => 'S', # U.S.-issuing bank does not support AVS.
        '20' => 'T', # Card member's name does not match, but street address matches.
        '21' => 'U', # Address information unavailable.
        '22' => 'V', # Card member's name, billing address, and billing postal code match.
        '23' => 'W', # Street address does not match, but 9-digit postal code matches.
        '24' => 'X', # Street address and 9-digit postal code match.
        '25' => 'Y', # Street address and 5-digit postal code match.
        '26' => 'Z'  # Street address does not match, but 5-digit postal code matches.
      }

      # Not implemented
      CVC_CODE_TRANSLATOR = {
        '1' => 'D', # CVV check flagged transaction as suspicious
        '2' => 'I', # CVV failed data validation check
        '3' => 'M', # CVV matches
        '4' => 'N', # CVV does not match
        '5' => 'P', # CVV not processed
        '6' => 'S', # CVV should have been present
        '7' => 'U', # CVV request unable to be processed by issuer
        '8' => 'X'  # CVV check not supported for card
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
        requires!(options, :login, :password)
        @merchant_id, @api_token = options[:login].split(":")
        @hash_secret = options[:password]

        super
      end

      def purchase(money, payment, options={})
        # This is combined Authorize and Capture in one transaction. Sometimes we just want to take a payment!
        # API reference: http://doc.mondido.com/api#transaction-create

        requires!(options, :order_id)
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

        ## New options introduced by Mondido Gateway
        #  :metadata    => (string) Metadata is custom schemaless information that you can choose to send in to Mondido.
        #                  It can be information about the customer, the product or about campaigns or offers.

        post = {
          # string* required
          # The ID of the merchant
          :merchant_id => @merchant_id.to_s,

          # decimal* required
          # The transaction amount ex. 12.00
          :amount => get_amount(money, options),

          # string* required
          # Merchant order/payment ID
          :payment_ref => options[:order_id].to_s,

          # boolean
          # Whether the transaction is a test transaction. Defaults false
          :test => test?,

          # string* required
          # The currency (SEK, CAD, CNY, COP, CZK, DKK, HKD, HUF, ISK, INR, ILS, JPY, KES, KRW,
          #  KWD, LVL, MYR, MXN, MAD, OMR, NZD, NOK, PAB, QAR, RUB, SAR, SGD, ZAR, CHF, THB, TTD,
          #  AED, GBP, USD, TWD, VEF, RON, TRY, EUR, UAH, PLN, BRL)
          :currency => get_currency(money, options),

          # string
          # The merchant specific user/customer ID
          :customer_ref => (options[:custom_ref] || '').to_s,

          # string * required
          # The hash is a MD5 encoded string with some of your merchant and order specific parameters,
          # which is used to verify the payment, and make sure that it is not altered in any way.
          :hash => transaction_hash_for(money, payment, options),

          # string * required
          # A URL to the page where the user is redirected after a unsuccessful transaction.
          :error_url => ""
        }

        # Metadata (string)
        # Merchant custom Metadata:
        #   Metadata is custom schemaless information that you can choose to send in to Mondido.
        #   It can be information about the customer, the product or about campaigns or offers.
        #
        #   The metadata can be used to customize your hosted payment window or sending personalized
        #   receipts to your customers in a webhook.
        post.merge!( :metadata => options[:metadata] ) if options[:metadata]
        
        add_credit_card(post, payment)
        #add_address(post, payment, options)
        #add_customer_data(post, options)

        commit(:post, 'transactions', post)
      end

      def authorize(money, payment, options={})
        # Validate the credit card and reserve the money for later collection

        # not implemented
        return
      end

      def capture(money, authorization, options={})
        # References a previous “Authorize” and requests that the money be drawn down.
        # It’s good practice (required) in many juristictions not to take a payment from a
        #   customer until the goods are shipped.

        # not implemented
        return
      end

      def refund(money, authorization, options={})
        # Refund money to a card.
        # This may need to be specifically enabled on your account and may not be supported by all gateways

        # not implemented
        return

        #post = {}
        #commit(:post, 'refunds', post)
      end

      def void(authorization, options={})
        # Entirely void a transaction.

        # not implemented
        return
      end

      def verify(credit_card, options={})
        # not implemented
        return

        #MultiResponse.run(:use_first_response) do |r|
        #  r.process { authorize(100, credit_card, options) }
        #  r.process(:ignore_result) { void(r.authorization, options) }
        #end
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
          gsub(%r((amount=)\w+), '\1[FILTERED]').
          gsub(%r((merchant_id=)\d+), '\1[FILTERED]')
      end

      private

      def transaction_hash_for(money, payment, options={})
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
        hash_attributes += options[:order_id].to_s                          # 2
        hash_attributes += ""                                               # 3
        hash_attributes += get_amount(money, options)                       # 4 #.round(2).to_s
        hash_attributes += get_currency(money, options)                     # 5
        hash_attributes += ((test?) ? "test" : "")                          # 6
        hash_attributes += @hash_secret                                     # 7

        md5 = Digest::MD5.new
        md5.update hash_attributes

        return md5.hexdigest
      end


      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_credit_card(post, credit_card)
        # Need to implement add_payment for tokenized cards
        # ...
        post[:card_holder] = credit_card.name if credit_card.name
        post[:card_cvv] = credit_card.verification_value if credit_card.verification_value?
        post[:card_expiry] = format(credit_card.month, :two_digits) + format(credit_card.year, :two_digits)
        post[:card_number] = credit_card.number
        post[:card_type] = ActiveMerchant::Billing::CreditCard.brand?(credit_card.number)
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

        # Not implemented yet
        avs_code = AVS_CODE_TRANSLATOR["25"]
        cvc_code = CVC_CODE_TRANSLATOR["3"]

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
puts "begin1"
puts method
puts self.live_url + uri
puts post_data(parameters)
puts headers(options)
          raw_response = ssl_request(
            method,
            self.live_url + uri,
            post_data(parameters),
            headers(options)
          )
puts raw_response.inspect

          response = parse(raw_response)
        rescue ResponseError => e

          raw_response = e.response.body
puts "rescue1"
puts e.inspect
puts e.response.inspect
puts raw_response.inspect
          response = response_error(raw_response)
        rescue JSON::ParserError
puts "rescue json"
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
