require 'openssl'
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

      self.supported_countries = %w(AT BE BG HR CY CZ DK EE FI FR DE GI GR HU IS IM IT LV LI 
        LT LU MC NL NO PL PT IE MT RO SK SI ES SE CH GB)

      self.supported_cardtypes = [:visa, :master, :discover, :american_express, 
          :diners_club, :jcb, :switch, :solo, :maestro, :laser]

      # Mapping of CVV check result codes from Mondido to CVVResult standard codes
      # For more codes, please check the CVVResult class
      CVC_CODE_TRANSLATOR = {
        'errors.card_cvv.missing' => 'S', # CVV should have been present
        'errors.card_cvv.invalid' => 'N', # CVV does not match
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

        # Optional: RSA Encryption
        if options[:public_key]
          begin
            @public_key = OpenSSL::PKey::RSA.new(options[:public_key])
          rescue OpenSSL::PKey::RSAError
            raise "Invalid RSA Key length or format"
          end
        end

        # Optional: Certificate Pinning
        if options[:certificate_for_pinning]
          begin
            @certificate_for_pinning = OpenSSL::X509::Certificate.new(options[:certificate_for_pinning])
          rescue OpenSSL::X509::CertificateError
            raise "Invalid Certificate length or format"
          end
        end

        super
      end

      def purchase(money, payment, options={})
        # This is combined Authorize and Capture in one transaction. Sometimes we just want to take a payment!
        # API reference: http://doc.mondido.com/api#transaction-create

        options[:authorize] = true
        create_post_for_auth_or_purchase(money, payment, options)
      end

      def authorize(money, payment, options={})
        # Validate the credit card and reserve the money for later collection

        options[:authorize] = false
        create_post_for_auth_or_purchase(money, payment, options)
      end

      def capture(money, authorization, options={})
        # References a previous “Authorize” and requests that the money be drawn down.
        # It’s good practice (required) in many juristictions not to take a payment from a
        #   customer until the goods are shipped.

        requires!(options, :amount)
        put = {
          # amount decimal *required 
          #   The amount to refund. Ex. 5.00
          :amount => get_amount(money, options)
        }

        commit(:put, "transactions/#{authorization}/capture", put)
      end

      def refund(money, authorization, options={})
        # Refund money to a card.
        # This may need to be specifically enabled on your account and may not be supported by all gateways

        requires!(options, :transaction_id, :reason)
        post = {
          # transaction_id  int *required
          #   ID for the transaction to refund
          :transaction_id => authorization.to_i,

          # amount decimal *required 
          #   The amount to refund. Ex. 5.00
          :amount => get_amount(money, options),

          # reason string *required
          #   The reason for the refund. Ex. "Cancelled order"
          :reason => options[:reason]
        }

        commit(:post, 'refunds', post)
      end

      def void(authorization, options={})
        # Entirely void a transaction.
        # Any amount into a refund will cancel the whole reservation

        refund(100, authorization, options)
      end

      def verify(credit_card, options={})
        # Test a payment authorizing a value of 1.00
        # Then void the transaction and refund the value

        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def store(payment, options = {})
        if options[:customer_ref].nil? and options[:customer_id].nil?
          raise "Parameter customer_ref or customer_id must be present."
        end

        post = {
          # currency  string* required
          :currency => options[:currency] || self.default_currency,

          # customer_ref  string
          #   Merchant specific customer ID.
          #   If this customer exists the card will be added to that customer.
          #   If it doesn't exists a customer will be created.
          :customer_ref => options[:customer_ref].to_s,

          # customer_id int
          #   Mondido specific customer ID.
          #   If this customer exists the card will be added to that customer.
          #   If it doesn't exists an error will occur.
          :customer_id => options[:customer_id],

          # encrypted (string)
          #   A comma separated string for the params that you send encrypted.
          #   Ex. "card_number,card_cvv"
          :encrypted => '',

          # test bool
          #   Must be true if you are using a test card number.
          :test => test?

        }

        add_encryption(post)
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
          :hash => transaction_hash_for(money, options),
        }

        ## API Optional Parameters
        #
        # - test
        # - authorize
        # - metadata
        # - plan id
        # - customer_ref
        # - webhook
        # - process

        # test (boolean)
        #   Whether the transaction is a test transaction. Defaults false
        post[:test] = test?

        # authorize (boolean)
        #   [ Not documented; default false ]
        post[:authorize] = options[:authorize]

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

        # process (boolean)
        #   Should be false if you want to process the payment at a later stage.
        #   You will not need to send in card data
        #   (card_number, card_cvv, card_holder, card_expiry) in this case.
        post.merge!( :process => options[:process] ) if options[:process]

        add_encryption(post)
        add_credit_card(post, payment)
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
        hash_attributes += options[:customer_ref].to_s                      # 3
        hash_attributes += get_amount(money, options)                       # 4
        hash_attributes += get_currency(money, options)                     # 5
        hash_attributes += ((test?) ? "test" : "")                          # 6
        hash_attributes += @hash_secret                                     # 7

        md5 = Digest::MD5.new
        md5.update hash_attributes

        return md5.hexdigest
      end

      def add_credit_card(post, credit_card)
        post[:card_holder] = credit_card.name if credit_card.name
        post[:card_cvv] = credit_card.verification_value if credit_card.verification_value?
        post[:card_expiry] = format(credit_card.month, :two_digits) + format(credit_card.year, :two_digits)
        post[:card_number] = credit_card.number

        # Stored card variables
        #   card_number => card_hash
        #   card_type   => 'stored_card'
        if credit_card.respond_to?(:brand)
          post[:card_type] = credit_card.brand
        else
          post[:card_type] = ActiveMerchant::Billing::CreditCard.brand?(credit_card.number)
        end
      end

      def add_encryption(post)
          # encrypted (string)
          #   A comma separated string for the params that you send encrypted.
          #   Ex. "card_number,card_cvv"
          post[:encrypted] = 'card_holder,card_number,card_cvv,card_expiry,card_type,hash,amount,payment_ref,customer_ref'
      end

      def get_amount(money, options)
        currency = get_currency(money, options)
        localized_amount(money, currency)
      end

      def get_currency(money, options)
        (options[:currency] || currency(money)).downcase
      end  

      def commit(method, uri, parameters = nil, options = {})
        # RSA Public Key Encryption
        if @public_key and parameters.is_a? Hash and parameters.key?(:encrypted)
          all_params = parameters[:encrypted].split(",")
          invalid_params = []

          all_params.each do |parameter|
            if parameters[:"#{parameter}"]
              encrypted_param = @public_key.public_encrypt(parameters[:"#{parameter}"])
              parameters[:"#{parameter}"] = Base64.encode64(encrypted_param)
            else
              invalid_params << parameter
            end
          end

          # Self-correctness of the "encrypted" param
          # In case it points invalid parameters.
          # For example: was expecting a optional parameter that, if passed, must be encrypted
          # If not present, this self-correct mechanism will update the "encrypted" parameter
          invalid_params.each do |invalid_param|
            all_params.delete(invalid_param)
          end

          parameters[:encrypted] = all_params.join(',')
        end

        # Perform Request
        response = api_request(method, uri, parameters, options)

        # Construct the Response object below:
        # Success of Response = absence of errors
        success = !(response.count==3 and response.key?("name") \
          and response.key?("code") and response.key?("description"))

        # Mondido doesn't check the purchase address vs billing address
        # So we use the standard code 'E'.
        # 'E' => AVS data is invalid or AVS is not allowed for this card type.
        # For more codes, please check the AVSResult class
        avs_code = 'E'

        # By default, we understand that the CVV matched (code "M")
        # But we find the error 124 or 125, we report the
        # related CVC Code to Active Merchant gem
        cvc_code = "M"
        if not success and ["errors.card_cvv.invalid","errors.card_cvv.missing"].include? response["name"]
          cvc_code = CVC_CODE_TRANSLATOR[ response["name"] ]
        end

        Response.new(
          success,
          (success ? "Transaction approved" : response["description"]),
          response,
          :test => response["test"],
          :authorization => success ? response["id"] : response["description"],
          :avs_result => { :code => avs_code },
          :cvv_result => cvc_code,
          :error_code => success ? nil : STANDARD_ERROR_CODE_TRANSLATOR[response["name"]]
        )
      end

      def api_request(method, uri, parameters = nil, options = {})
        raw_response = response = nil
        begin
          if @certificate_for_pinning
            uri = URI.parse(self.live_url + uri)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.verify_callback = lambda do | preverify_ok, cert_store |
              return false unless preverify_ok

              # We only want to verify once, and fail the first time the callback
              # is invoked (as opposed to checking only the last time it's called).
              # Therefore we get at the whole authorization chain.
              # The end certificate is at the beginning of the chain (the certificate
              # for the host we are talking to)
              end_cert = cert_store.chain[0]

              # Only perform the checks if the current cert is the end certificate
              # in the chain. We can compare using the DER representation
              # (OpenSSL::X509::Certificate objects are not comparable, and for 
              # a good reason). If we don't we are going to perform the verification
              # many times - once per certificate in the chain of trust, which is wasteful
              return true unless end_cert.to_der == cert_store.current_cert.to_der

              # And verify the public key and the certificate fingerprint
              if same_public_key?(end_cert, @certificate_for_pinning) \
                and same_cert_fingerprint?(end_cert, @certificate_for_pinning)
                  return true
              else
                  return false
              end
            end

            # Request Object
            request = eval "Net::HTTP::#{method.capitalize}.new(uri.request_uri)"

            # Post Data
            request.set_form_data(parameters) if parameters

            # Add Headers
            all_headers = headers(options)
            all_headers.keys.each do |header|
              request.add_field(header, all_headers[header])
            end

            # Response
            begin
              raw_response = http.request(request)
            rescue OpenSSL::SSL::SSLError
              raise "Security Problem: pinned certificate doesn't match the server certificate."
            end
            raw_response_body = raw_response.body
          else
            raw_response_body = ssl_request(
              method,
              self.live_url + uri,
              post_data(parameters),
              headers(options)
            )
          end

          response = parse(raw_response_body)
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end

        response
      end

      def same_public_key?(ref_cert, actual_cert)
        pkr, pka = ref_cert.public_key, actual_cert.public_key

        # First check if the public keys use the same crypto...
        return false unless pkr.class == pka.class
        # ...and then - that they have the same contents
        return false unless pkr.to_pem == pka.to_pem

        true
      end

      def same_cert_fingerprint?(ref_cert, actual_cert)
        OpenSSL::Digest::SHA256.hexdigest(ref_cert.to_der) ==  OpenSSL::Digest::SHA256.hexdigest(actual_cert.to_der)
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
