require 'test_helper'

class RemoteMondidoTest < Test::Unit::TestCase
  def setup
    start_params = fixtures(:mondido)

    # Gateway with Public Key Crypto (and Certificate Pinning)
    start_params.delete :certificate_hash_for_pinning
    start_params.delete :public_key_for_pinning
    @gateway_encrypted = MondidoGateway.new(start_params)

    # Gateway without Public Key Crypto (and Certificate Pinning)
    start_params.delete :public_key
    @gateway = MondidoGateway.new(start_params)

    @amount = 1000 # $ 10.00
    @credit_card = credit_card('4111111111111111', { verification_value: '200' })
    @declined_card = credit_card('4111111111111111', { verification_value: '201' })
    @cvv_invalid_card = credit_card('4111111111111111', { verification_value: '202' })
    @expired_card = credit_card('4111111111111111', { verification_value: '203' })

    @stored_card = credit_card('', { brand: 'stored_card' })
    @declined_stored_card = credit_card('', { brand: 'stored_card' })


    # The @base_order_id is for test purposes
    # As could not exist more than one transaction using the same payment_ref value,
    # To prevent different methods from using the same order_id, I just increment the
    # test_iteration value in 1 and it will serve as a factor to change the order_id in
    # every test method. This way there will be no duplicates and all tests will respect
    # some base number (200000000 in this case).
    test_iteration = 15
    @counter = 1
    @remote_mondido_test_methods = (RemoteMondidoTest.instance_methods - Object.methods)
    @number_of_test_methods = @remote_mondido_test_methods.count
    @base_order_id = (200000000 + (test_iteration * @number_of_test_methods))
    @options = { test: true }
  end

  def generate_order_id
    order_id = (@base_order_id + @counter).to_s + Time.now.to_s
    @counter += 1
    return order_id
  end

  def generate_recurring
    100
  end

  def generate_webhook
      {
        "trigger" => "payment_success",
        "email" => "user@hook.com"
      }.to_json
  end

  def generate_metadata
    {
      "products" => [
      {
        "id" => "1",
        "name" => "Nice Shoe",
        "price" => "100.00",
        "qty" => "1",
        "url" => "http://mondido.com/product/1"
      }
      ],
      "user" => {
        "email" => "user@email.com"
      }
    }.to_json
  end

  def purchase_response(new_options, encryption, authorize, stored_card, failure)
    gateway = encryption ? @gateway_encrypted : @gateway
    card = stored_card ? @stored_card : @credit_card
    declined_card = stored_card ? @declined_stored_card : @declined_card

    return (authorize ?
      gateway.authorize(@amount, (failure ? declined_card : card), new_options)
        :
      gateway.purchase(@amount, (failure ? declined_card : card), new_options)
    )
  end

  def purchase_successful(new_options, encryption, authorize, stored_card)
    response = purchase_response(new_options, encryption, authorize, stored_card, false)

    assert_success response
    assert_equal new_options[:order_id], response.params["payment_ref"]
    assert_equal "approved", response.params["status"]
  end

  def purchase_failure(new_options, encryption, authorize, stored_card)
    response = purchase_response(new_options, encryption, authorize, stored_card, true)

    assert_failure response
    assert_equal "errors.payment.declined", response.params["name"]
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
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
      }))
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
    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_failure response
  end

  def test_valid_pinned_certificate
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_hash_for_pinning] = nil
    start_params[:public_key_for_pinning] = nil
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_success response
  end

  def test_invalid_pinned_certificate
    invalid_certificate = "-----BEGIN CERTIFICATE-----
MIIGxTCCBa2gAwIBAgIIAl5EtcNJFrcwDQYJKoZIhvcNAQEFBQAwSTELMAkGA1UE
BhMCVVMxEzARBgNVBAoTCkdvb2dsZSBJbmMxJTAjBgNVBAMTHEdvb2dsZSBJbnRl
cm5ldCBBdXRob3JpdHkgRzIwHhcNMTQxMjEwMTEzMzM3WhcNMTUwMzEwMDAwMDAw
WjBmMQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwN
TW91bnRhaW4gVmlldzETMBEGA1UECgwKR29vZ2xlIEluYzEVMBMGA1UEAwwMKi5n
b29nbGUuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEmng6ZoVeVmmAplSC
9TcTQkkosO5zaPDTXLuuzQU3Bl5JUSF/11w6dlXdJJHXIQ3cIirUuyd288ORbu93
FrTTTaOCBF0wggRZMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjCCAyYG
A1UdEQSCAx0wggMZggwqLmdvb2dsZS5jb22CDSouYW5kcm9pZC5jb22CFiouYXBw
ZW5naW5lLmdvb2dsZS5jb22CEiouY2xvdWQuZ29vZ2xlLmNvbYIWKi5nb29nbGUt
YW5hbHl0aWNzLmNvbYILKi5nb29nbGUuY2GCCyouZ29vZ2xlLmNsgg4qLmdvb2ds
ZS5jby5pboIOKi5nb29nbGUuY28uanCCDiouZ29vZ2xlLmNvLnVrgg8qLmdvb2ds
ZS5jb20uYXKCDyouZ29vZ2xlLmNvbS5hdYIPKi5nb29nbGUuY29tLmJygg8qLmdv
b2dsZS5jb20uY2+CDyouZ29vZ2xlLmNvbS5teIIPKi5nb29nbGUuY29tLnRygg8q
Lmdvb2dsZS5jb20udm6CCyouZ29vZ2xlLmRlggsqLmdvb2dsZS5lc4ILKi5nb29n
bGUuZnKCCyouZ29vZ2xlLmh1ggsqLmdvb2dsZS5pdIILKi5nb29nbGUubmyCCyou
Z29vZ2xlLnBsggsqLmdvb2dsZS5wdIISKi5nb29nbGVhZGFwaXMuY29tgg8qLmdv
b2dsZWFwaXMuY26CFCouZ29vZ2xlY29tbWVyY2UuY29tghEqLmdvb2dsZXZpZGVv
LmNvbYIMKi5nc3RhdGljLmNugg0qLmdzdGF0aWMuY29tggoqLmd2dDEuY29tggoq
Lmd2dDIuY29tghQqLm1ldHJpYy5nc3RhdGljLmNvbYIMKi51cmNoaW4uY29tghAq
LnVybC5nb29nbGUuY29tghYqLnlvdXR1YmUtbm9jb29raWUuY29tgg0qLnlvdXR1
YmUuY29tghYqLnlvdXR1YmVlZHVjYXRpb24uY29tggsqLnl0aW1nLmNvbYILYW5k
cm9pZC5jb22CBGcuY2+CBmdvby5nbIIUZ29vZ2xlLWFuYWx5dGljcy5jb22CCmdv
b2dsZS5jb22CEmdvb2dsZWNvbW1lcmNlLmNvbYIKdXJjaGluLmNvbYIIeW91dHUu
YmWCC3lvdXR1YmUuY29tghR5b3V0dWJlZWR1Y2F0aW9uLmNvbTALBgNVHQ8EBAMC
B4AwaAYIKwYBBQUHAQEEXDBaMCsGCCsGAQUFBzAChh9odHRwOi8vcGtpLmdvb2ds
ZS5jb20vR0lBRzIuY3J0MCsGCCsGAQUFBzABhh9odHRwOi8vY2xpZW50czEuZ29v
Z2xlLmNvbS9vY3NwMB0GA1UdDgQWBBTn6rT+UWACLuZnUas2zTQJkdrq5jAMBgNV
HRMBAf8EAjAAMB8GA1UdIwQYMBaAFErdBhYbvPZotXb1gba7Yhq6WoEvMBcGA1Ud
IAQQMA4wDAYKKwYBBAHWeQIFATAwBgNVHR8EKTAnMCWgI6Ahhh9odHRwOi8vcGtp
Lmdvb2dsZS5jb20vR0lBRzIuY3JsMA0GCSqGSIb3DQEBBQUAA4IBAQBb4wU7IjXL
msvaYqFlYYDKiYZhBUGHxxLkFWR72vFugYkJ7BbMCaKZJdyln5xL4pCdNHiNGfub
/3ct2t3sKeruc03EydznLQ78qrHuwNJdqUZfDLJ6ILAQUmpnYEXrnmB7C5chCWR0
OKWRLguwZQQQQlRyjZFtdoISHNveel/UkS/Jwijvpbw/wGg9W4L4En6RjDeD259X
zYvNzIwiEq50/5ZQCYE9EH0mWguAji9tuh5NJKPEeaaCQ3lp/UEAkq5uYls7tuSs
MTI9LMZRiYFJab/LYbq2uaz4B/lSuE9vku+ikNYA+J2Qv6eqU3U+jmUOSCfYJ2Qt
zSl8TUu4bL8a
-----END CERTIFICATE-----
"
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_for_pinning] = invalid_certificate
    start_params[:certificate_hash_for_pinning] = nil
    start_params[:public_key_for_pinning] = nil
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_failure response
    assert_equal "Security Problem: pinned certificate doesn't match the server certificate.", response.message
  end

  def test_valid_pinned_certificate_hash
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_for_pinning] = nil
    start_params[:public_key_for_pinning] = nil
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_success response
  end

  def test_invalid_pinned_certificate_hash
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_for_pinning] = nil
    start_params[:public_key_for_pinning] = nil
    start_params[:certificate_hash_for_pinning] = "invalid hash"
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_failure response
    assert_equal "Security Problem: pinned certificate doesn't match the server certificate.", response.message
  end

  def test_valid_pinned_public_key
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_for_pinning] = nil
    start_params[:certificate_hash_for_pinning] = nil
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_success response
  end

  def test_invalid_pinned_public_key
    start_params = fixtures(:mondido)
    start_params[:public_key] = nil
    start_params[:certificate_for_pinning] = nil
    start_params[:certificate_hash_for_pinning] = nil
    start_params[:public_key_for_pinning] = "-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1GyXNJG2Tzwof4z4S0Dz
hhY8Ht3gdoO8N4YKdPH+hkRDgtLlOyTB9YZ+3QJh77aed7xBlHXdZ9dlTeCmGUOM
rHARGh845Iu1GfdgM8+L3TFeOsNgy2xeHCdIjSbYbHcj13tdOBsKQyn6BRVR8+Ym
a2WKXVN3lOgWlr/NEeBwiwQZW4F4WUEqQSEpNFfGAReW0EMUalPWoXMgyxWDL7/A
kax11h+O8HKK/D0flGF/ZRfY5ybyYbQWaMWSfo0pSeay1m7Irbae4YW9gI1YKrmB
JiLNKynvxE4IbTpKzug77yi8L1tMJsn65QMEYlpus4GvSn3PHAz5unA/9YX7gjyO
ZwIDAQAB
-----END PUBLIC KEY-----"
    gateway = MondidoGateway.new(start_params)

    response = gateway.purchase(@amount, @credit_card, @options.merge({
        :order_id => generate_order_id
    }))
    assert_failure response
    assert_equal "Security Problem: pinned public key doesn't match the server public key.", response.message
  end


  ## 3. Purchase
  #

  # With Encryption
  # With Credit Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_webhook_metadata
    test_successful_purchase_credit_card_recurring_webhook_metadata(true)
  end

  def test_failed_purchase_encryption_credit_card_recurring_webhook_metadata
    test_failed_purchase_credit_card_recurring_webhook_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_webhook
    test_successful_purchase_credit_card_recurring_webhook(true)
  end

  def test_failed_purchase_encryption_credit_card_recurring_webhook
    test_failed_purchase_credit_card_recurring_webhook(true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_recurring_metadata
    test_successful_purchase_credit_card_recurring_metadata(true)
  end

  def test_failed_purchase_encryption_credit_card_recurring_metadata
    test_failed_purchase_credit_card_recurring_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_recurring
    test_successful_purchase_credit_card_recurring(true)
  end

  def test_failed_purchase_encryption_credit_card_recurring
    test_failed_purchase_credit_card_recurring(true)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_webhook_metadata
    test_successful_purchase_credit_card_webhook_metadata(true)
  end

  def test_failed_purchase_encryption_credit_card_webhook_metadata
    test_failed_purchase_credit_card_webhook_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card_webhook
    test_successful_purchase_credit_card_webhook(true)
  end

  def test_failed_purchase_encryption_credit_card_webhook
    test_failed_purchase_credit_card_webhook(true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_credit_card_metadata
    test_successful_purchase_credit_card_metadata(true)
  end

  def test_failed_purchase_encryption_credit_card_metadata
    test_failed_purchase_credit_card_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_credit_card
    test_successful_purchase_credit_card(true)
  end

  def test_failed_purchase_encryption_credit_card
    test_failed_purchase_credit_card(true)
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_webhook_metadata
    test_successful_purchase_stored_card_recurring_webhook_metadata(true)
  end

  def test_failed_purchase_encryption_stored_card_recurring_webhook_metadata
    test_failed_purchase_stored_card_recurring_webhook_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_webhook
    test_successful_purchase_stored_card_recurring_webhook(true)
  end

  def test_failed_purchase_encryption_stored_card_recurring_webhook
    test_failed_purchase_stored_card_recurring_webhook(true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_recurring_metadata
    test_successful_purchase_stored_card_recurring_metadata(true)
  end

  def test_failed_purchase_encryption_stored_card_recurring_metadata
    test_failed_purchase_stored_card_recurring_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_recurring
    test_successful_purchase_stored_card_recurring(true)
  end

  def test_failed_purchase_encryption_stored_card_recurring
    test_failed_purchase_stored_card_recurring(true)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_webhook_metadata
    test_successful_purchase_stored_card_webhook_metadata(true)
  end

  def test_failed_purchase_encryption_stored_card_webhook_metadata
    test_failed_purchase_stored_card_webhook_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card_webhook
    test_successful_purchase_stored_card_webhook(true)
  end

  def test_failed_purchase_encryption_stored_card_webhook
    test_failed_purchase_stored_card_webhook(true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_encryption_stored_card_metadata
    test_successful_purchase_stored_card_metadata(true)
  end

  def test_failed_purchase_encryption_stored_card_metadata
    test_failed_purchase_stored_card_metadata(true)
  end

  # Without Meta Data

  def test_successful_purchase_encryption_stored_card
    test_successful_purchase_stored_card(true)
  end

  def test_failed_purchase_encryption_stored_card
    test_failed_purchase_stored_card(true)
  end

  # Without Encryption

  def test_successful_purchase_credit_card_recurring_webhook_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :webhook => generate_webhook,
      :metadata => generate_metadata
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_recurring_webhook_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :webhook => generate_webhook,
      :metadata => generate_metadata
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_recurring_webhook(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :webhook => generate_webhook
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_recurring_webhook(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :webhook => generate_webhook
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_credit_card_recurring_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :metadata => generate_metadata
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_recurring_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring,
      :metadata => generate_metadata
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_recurring(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_recurring(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :plan_id => generate_recurring
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Recurring

  # With Web Hook

  # With Meta Data

  def test_successful_purchase_credit_card_webhook_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :webhook => generate_webhook,
      :metadata => generate_metadata
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_webhook_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :webhook => generate_webhook,
      :metadata => generate_metadata
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_credit_card_webhook(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :webhook => generate_webhook
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_webhook(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :webhook => generate_webhook
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_credit_card_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :metadata => generate_metadata
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card_metadata(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id,
      :metadata => generate_metadata
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_credit_card(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id
    })
    purchase_successful(new_options, encryption, authorize, stored)
  end

  def test_failed_purchase_credit_card(encryption=false, authorize=false, stored=false)
    new_options = @options.merge({
      :order_id => generate_order_id
    })
    purchase_failure(new_options, encryption, authorize, stored)
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_purchase_stored_card_recurring_webhook_metadata(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_recurring_webhook_metadata(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_recurring_webhook_metadata(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_recurring_webhook_metadata(encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_recurring_webhook(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_recurring_webhook(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_recurring_webhook(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_recurring_webhook
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_stored_card_recurring_metadata(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_recurring_metadata(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_recurring_metadata(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_recurring_metadata(encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_recurring(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_recurring(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_recurring(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_recurring(encryption, authorize, stored)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_purchase_stored_card_webhook_metadata(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_webhook_metadata(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_webhook_metadata(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_webhook_metadata(encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_stored_card_webhook(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_webhook(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_webhook(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_webhook(encryption, authorize, stored)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_purchase_stored_card_metadata(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card_metadata(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card_metadata(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card_metadata(encryption, authorize, stored)
  end

  # Without Meta Data

  def test_successful_purchase_stored_card(encryption=false, authorize=false, stored=true)
    test_successful_purchase_credit_card(encryption, authorize, stored)
  end

  def test_failed_purchase_stored_card(encryption=false, authorize=false, stored=true)
    test_failed_purchase_credit_card(encryption, authorize, stored)
  end

=begin
  ## 4. Authorize
  #

  def test_successful_authorize_encryption_credit_card_recurring_webhook_metadata
    test_successful_purchase_credit_card_recurring_webhook_metadata(true, true)
  end

  def test_failed_authorize_encryption_credit_card_recurring_webhook_metadata
    test_failed_purchase_credit_card_recurring_webhook_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_credit_card_recurring_webhook
    test_successful_purchase_credit_card_recurring_webhook(true, true)
  end

  def test_failed_authorize_encryption_credit_card_recurring_webhook
    test_failed_purchase_credit_card_recurring_webhook(true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_encryption_credit_card_recurring_metadata
    test_successful_purchase_credit_card_recurring_metadata(true, true)
  end

  def test_failed_authorize_encryption_credit_card_recurring_metadata
    test_failed_purchase_credit_card_recurring_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_credit_card_recurring
    test_successful_purchase_credit_card_recurring(true, true)
  end

  def test_failed_authorize_encryption_credit_card_recurring
    test_failed_purchase_credit_card_recurring(true, true)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_authorize_encryption_credit_card_webhook_metadata
    test_successful_purchase_credit_card_webhook_metadata(true, true)
  end

  def test_failed_authorize_encryption_credit_card_webhook_metadata
    test_failed_purchase_credit_card_webhook_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_credit_card_webhook
    test_successful_purchase_credit_card_webhook(true, true)
  end

  def test_failed_authorize_encryption_credit_card_webhook
    test_failed_purchase_credit_card_webhook(true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_encryption_credit_card_metadata
    test_successful_purchase_credit_card_metadata(true, true)
  end

  def test_failed_authorize_encryption_credit_card_metadata
    test_failed_purchase_credit_card_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_credit_card
    test_successful_purchase_credit_card(true, true)
  end

  def test_failed_authorize_encryption_credit_card
    test_failed_purchase_credit_card(true, true)
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_authorize_encryption_stored_card_recurring_webhook_metadata
    test_successful_purchase_stored_card_recurring_webhook_metadata(true, true)
  end

  def test_failed_authorize_encryption_stored_card_recurring_webhook_metadata
    test_failed_purchase_stored_card_recurring_webhook_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_stored_card_recurring_webhook
    test_successful_purchase_stored_card_recurring_webhook(true, true)
  end

  def test_failed_authorize_encryption_stored_card_recurring_webhook
    test_failed_purchase_stored_card_recurring_webhook(true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_encryption_stored_card_recurring_metadata
    test_successful_purchase_stored_card_recurring_metadata(true, true)
  end

  def test_failed_authorize_encryption_stored_card_recurring_metadata
    test_failed_purchase_stored_card_recurring_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_stored_card_recurring
    test_successful_purchase_stored_card_recurring(true, true)
  end

  def test_failed_authorize_encryption_stored_card_recurring
    test_failed_purchase_stored_card_recurring(true, true)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_authorize_encryption_stored_card_webhook_metadata
    test_successful_purchase_stored_card_webhook_metadata(true, true)
  end

  def test_failed_authorize_encryption_stored_card_webhook_metadata
    test_failed_purchase_stored_card_webhook_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_stored_card_webhook
    test_successful_purchase_stored_card_webhook(true, true)
  end

  def test_failed_authorize_encryption_stored_card_webhook
    test_failed_purchase_stored_card_webhook(true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_encryption_stored_card_metadata
    test_successful_purchase_stored_card_metadata(true, true)
  end

  def test_failed_authorize_encryption_stored_card_metadata
    test_failed_purchase_stored_card_metadata(true, true)
  end

  # Without Meta Data

  def test_successful_authorize_encryption_stored_card
    test_successful_purchase_stored_card(true, true)
  end

  def test_failed_authorize_encryption_stored_card
    test_failed_purchase_stored_card(true, true)
  end

  # Without Encryption

  def test_successful_authorize_credit_card_recurring_webhook_metadata
    test_successful_purchase_credit_card_recurring_webhook_metadata(false, true, false)
  end

  def test_failed_authorize_credit_card_recurring_webhook_metadata
    test_failed_purchase_credit_card_recurring_webhook_metadata(false, true, false)
  end

  # Without Meta Data

  def test_successful_authorize_credit_card_recurring_webhook
    test_successful_purchase_credit_card_recurring_webhook(false, true, false)
  end

  def test_failed_authorize_credit_card_recurring_webhook
    test_failed_purchase_credit_card_recurring_webhook(false, true, false)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_credit_card_recurring_metadata
    test_successful_purchase_credit_card_recurring_metadata(false, true, false)
  end

  def test_failed_authorize_credit_card_recurring_metadata
    test_failed_purchase_credit_card_recurring_metadata(false, true, false)
  end

  # Without Meta Data

  def test_successful_authorize_credit_card_recurring
    test_successful_purchase_credit_card_recurring(false, true, false)
  end

  def test_failed_authorize_credit_card_recurring
    test_failed_purchase_credit_card_recurring(false, true, false)
  end

  # Without Recurring

  # With Web Hook

  # With Meta Data

  def test_successful_authorize_credit_card_webhook_metadata
    test_successful_purchase_credit_card_webhook_metadata(false, true, false)
  end

  def test_failed_authorize_credit_card_webhook_metadata
    test_failed_purchase_credit_card_webhook_metadata(false, true, false)
  end

  # Without Meta Data

  def test_successful_authorize_credit_card_webhook
    test_successful_purchase_credit_card_webhook(false, true, false)
  end

  def test_failed_authorize_credit_card_webhook
    test_failed_purchase_credit_card_webhook(false, true, false)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_credit_card_metadata
    test_successful_purchase_credit_card_metadata(false, true, false)
  end

  def test_failed_authorize_credit_card_metadata
    test_failed_purchase_credit_card_metadata(false, true, false)
  end

  # Without Meta Data

  def test_successful_authorize_credit_card
    test_successful_purchase_credit_card(false, true, false)
  end

  def test_failed_authorize_credit_card
    test_failed_purchase_credit_card(false, true, false)
  end

  # With Stored Card
  # With Recurring
  # With Web Hooks
  # With Meta Data

  def test_successful_authorize_stored_card_recurring_webhook_metadata
    test_successful_purchase_credit_card_recurring_webhook_metadata(false, true, true)
  end

  def test_failed_authorize_stored_card_recurring_webhook_metadata
    test_failed_purchase_credit_card_recurring_webhook_metadata(false, false, true)
  end

  # Without Meta Data

  def test_successful_authorize_stored_card_recurring_webhook
    test_successful_purchase_credit_card_recurring_webhook(false, false, true)
  end

  def test_failed_authorize_stored_card_recurring_webhook
    test_failed_purchase_credit_card_recurring_webhook(false, true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_stored_card_recurring_metadata
    test_successful_purchase_credit_card_recurring_metadata(false, true, true)
  end

  def test_failed_authorize_stored_card_recurring_metadata
    test_failed_purchase_credit_card_recurring_metadata(false, true, true)
  end

  # Without Meta Data

  def test_successful_authorize_stored_card_recurring
    test_successful_purchase_credit_card_recurring(false, true, true)
  end

  def test_failed_authorize_stored_card_recurring
    test_failed_purchase_credit_card_recurring(false, true, true)
  end

  # Without Recurring

  # With Meta Data

  def test_successful_authorize_stored_card_webhook_metadata
    test_successful_purchase_credit_card_webhook_metadata(false, true, true)
  end

  def test_failed_authorize_stored_card_webhook_metadata
    test_failed_purchase_credit_card_webhook_metadata(false, true, true)
  end

  # Without Meta Data

  def test_successful_authorize_stored_card_webhook
    test_successful_purchase_credit_card_webhook(false, true, true)
  end

  def test_failed_authorize_stored_card_webhook
    test_failed_purchase_credit_card_webhook(false, true, true)
  end

  # Without Web Hooks

  # With Meta Data

  def test_successful_authorize_stored_card_metadata
    test_successful_purchase_credit_card_metadata(false, true, true)
  end

  def test_failed_authorize_stored_card_metadata
    test_failed_purchase_credit_card_metadata(false, true, true)
  end

  # Without Meta Data

  def test_successful_authorize_stored_card
    test_successful_purchase_credit_card(false, true, true)
  end

  def test_failed_authorize_stored_card
    test_failed_purchase_credit_card(false, true, true)
  end

  # ...

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
