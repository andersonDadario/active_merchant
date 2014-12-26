require 'test_helper'

class RemoteMondidoTest < Test::Unit::TestCase
  def setup
    @gateway = MondidoGateway.new(fixtures(:mondido))

    @amount = 100 # $ 1.00
    @credit_card = credit_card('4111111111111111', { verification_value: '200' })
    @declined_card = credit_card('4111111111111111', { verification_value: '201' })
    @cvv_invalid_card = credit_card('4111111111111111', { verification_value: '202' })
    @expired_card = credit_card('4111111111111111', { verification_value: '203' })

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

  def test_successful_purchase
    @options[:order_id] = (@base_order_id + @remote_mondido_test_methods.index(__method__))

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Transaction approved', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_equal 'errors.payment.declined', response.params["name"]
    assert_equal response.params["description"], response.message
  end

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

  def test_invalid_login
    gateway = MondidoGateway.new(
      merchant_id: '',
      api_token: '',
      hash_secret: ''
    )
    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end
end
