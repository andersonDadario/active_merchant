require 'test_helper'

class RemoteMondidoTest < Test::Unit::TestCase
  def setup
    start_params = fixtures(:mondido)

    # Gateway with Public Key Crypto and Certificate Pinning
    @gateway_encrypted_with_cert_pinning = MondidoGateway.new(start_params)

    # Gateway with Public Key Crypto
    start_params.delete :certificate_for_pinning
    @gateway_encrypted = MondidoGateway.new(start_params)

    # Gateway without Public Key Crypto
    start_params.delete :public_key
    @gateway = MondidoGateway.new(start_params)

    @amount = 100 # $ 1.00
    @credit_card = credit_card('4111111111111111', { verification_value: '200' })
    @declined_card = credit_card('4111111111111111', { verification_value: '201' })
    @cvv_invalid_card = credit_card('4111111111111111', { verification_value: '202' })
    @expired_card = credit_card('4111111111111111', { verification_value: '203' })

    # Constants
    TRANSACTION_APPROVED = "Transaction approved"

    # The @base_order_id is for test purposes
    # As could not exist more than one transaction using the same payment_ref value,
    # To prevent different methods from using the same order_id, I just increment the
    # test_iteration value in 1 and it will serve as a factor to change the order_id in
    # every test method. This way there will be no duplicates and all tests will respect
    # some base number (200000000 in this case).
    test_iteration = 9
    @remote_mondido_test_methods = (RemoteMondidoTest.instance_methods - Object.methods)
    number_of_test_methods = @remote_mondido_test_methods.count
    @base_order_id = (200000000 + (test_iteration * number_of_test_methods)) 
    @options = { order_id: @base_order_id }
  end

  # CAUTION: You may get lost in the weeds to understand how these tests are structured.
  # Please access the documentation of MondidoGateway and look for the "Remote Tests
  # Coverage" to see the big picture. Do it before scrolling down.
  #
  # 1. Scrubbing
  # 2. Initialize/Login
  # 3. Purchase
  # 4. Authorize
  # 5. Capture
  # 6. Refund
  # 7. Void
  # 8. Verify
  # 9. Store
  # 10. Unstore


  ## 1. Scrubbing
  #

  def test_dump_transcript
    skip("Transcript scrubbing for this gateway has been tested.")

    # This test will run a purchase transaction on your gateway
    # and dump a transcript of the HTTP conversation so that
    # you can use that transcript as a reference while
    # implementing your scrubbing logic
    #dump_transcript_and_fail(@gateway, @amount, @credit_card, @options)
  end

  def test_transcript_scrubbing
    @options[:order_id] = (@base_order_id + @remote_mondido_test_methods.index(__method__))

    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed("card_cvv=#{@credit_card.verification_value}", transcript)
    assert_scrubbed(@gateway.options[:api_token], transcript)
    assert_scrubbed(@gateway.options[:hash_secret], transcript)

    b64_value = Base64.encode64(
      fixtures(:mondido)[:merchant_id].to_s + ":" + fixtures(:mondido)[:api_token]
    ).strip
    assert_scrubbed("Authorization: Basic #{b64_value}", transcript)
  end

  ## 2. Initialize/Login
  #

  def test_invalid_login
    gateway = MondidoGateway.new(
      merchant_id: '',
      api_token: '',
      hash_secret: ''
    )
    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  ## 3. Purchase
  #

  # With Encryption
  # With Credit Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_webhook_metadata
    @options[:order_id] = (@base_order_id + @remote_mondido_test_methods.index(__method__))

    response = @gateway_encrypted.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal TRANSACTION_APPROVED, response.message
  end

  def test_failed_purchase_encryption_credit_card_recurring_webhook_metadata
    response = @gateway_encrypted.purchase(@amount, @declined_card, @options)
    assert_equal 'errors.payment.declined', response.params["name"]
    assert_equal response.params["description"], response.message
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_webhook
  end

  def test_failed_purchase_encryption_credit_card_recurring_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_metadata
  end

  def test_failed_purchase_encryption_credit_card_recurring_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_recurring
  end

  def test_failed_purchase_encryption_credit_card_recurring
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_webhook_metadata
  end

  def test_failed_purchase_encryption_credit_card_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_webhook
  end

  def test_failed_purchase_encryption_credit_card_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_metadata
  end

  def test_failed_purchase_encryption_credit_card_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card
  end

  def test_failed_purchase_encryption_credit_card
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_webhook_metadata
  end

  def test_failed_purchase_encryption_stored_card_recurring_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_webhook
  end

  def test_failed_purchase_encryption_stored_card_recurring_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_metadata
  end

  def test_failed_purchase_encryption_stored_card_recurring_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_recurring
  end

  def test_failed_purchase_encryption_stored_card_recurring
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_webhook_metadata
  end

  def test_failed_purchase_encryption_stored_card_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_webhook
  end

  def test_failed_purchase_encryption_stored_card_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_metadata
  end

  def test_failed_purchase_encryption_stored_card_metadata
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card
  end

  def test_failed_purchase_encryption_stored_card
  end

  # Without Encryption

    def test_successful_purchase_credit_card_recurring_webhook_metadata
  end

  def test_failed_purchase_credit_card_recurring_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_recurring_webhook
  end

  def test_failed_purchase_credit_card_recurring_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_credit_card_recurring_metadata
  end

  def test_failed_purchase_credit_card_recurring_metadata
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_recurring
  end

  def test_failed_purchase_credit_card_recurring
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_credit_card_webhook_metadata
  end

  def test_failed_purchase_credit_card_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_webhook
  end

  def test_failed_purchase_credit_card_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_credit_card_metadata
  end

  def test_failed_purchase_credit_card_metadata
  end

  # Without Meta Data

  def test_successful_purchase_credit_card
  end

  def test_failed_purchase_credit_card
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_stored_card_recurring_webhook_metadata
  end

  def test_failed_purchase_stored_card_recurring_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_recurring_webhook
  end

  def test_failed_purchase_stored_card_recurring_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_stored_card_recurring_metadata
  end

  def test_failed_purchase_stored_card_recurring_metadata
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_recurring
  end

  def test_failed_purchase_stored_card_recurring
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_stored_card_webhook_metadata
  end

  def test_failed_purchase_stored_card_webhook_metadata
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_webhook
  end

  def test_failed_purchase_stored_card_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_stored_card_metadata
  end

  def test_failed_purchase_stored_card_metadata
  end

  # Without Meta Data

  def test_successful_purchase_stored_card
  end

  def test_failed_purchase_stored_card
  end

  # ....

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_equal 'errors.payment.declined', response.params["name"]
    assert_equal response.params["description"], response.message
  end

  ## 4. Authorize
  #
=begin
  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(nil, auth.authorization)
    assert_success capture
  end

  def test_failed_authorize
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
  end
=end

  ## 5. Capture
  #
=begin
  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount-1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(nil, '')
    assert_failure response
  end
=end

  ## 6. Refund
  #
=begin
  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(nil, purchase.authorization)
    assert_success refund
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount-1, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(nil, '')
    assert_failure response
  end
=end

  ## 7. Void
  #
=begin
  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
  end
=end

  ## 8. Verify
  #
=begin
    def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{REPLACE WITH SUCCESS MESSAGE}, response.message
  end

  def test_failed_verify
    response = @gateway.verify(@declined_card, @options)
    assert_failure response
    assert_match %r{REPLACE WITH FAILED PURCHASE MESSAGE}, response.message
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end
=end

  ## 9. Store
  #

  ## 10. Unstore
  #

end
