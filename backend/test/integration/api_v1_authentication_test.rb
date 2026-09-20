require "test_helper"

class ApiV1AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @organization = Organization.create!(name: "Auth Group")
    @user = User.create!(organization: @organization, name: "Inspector", email: "auth@example.com", password: "password123", role: "inspector")
  end

  test "login returns a token with an expiry and stores only its digest" do
    freeze_time do
      token = login

      assert_equal ApiToken::TTL.from_now.as_json, response.parsed_body["expires_at"]
      record = ApiToken.find_by!(token_digest: ApiToken.digest(token))
      assert_equal @user, record.user
      assert_not_equal token, record.token_digest
      assert_nil ApiToken.find_by(token_digest: token)
    end
  end

  test "an expired token is rejected" do
    token = login
    ApiToken.update_all(expires_at: 1.minute.ago)

    get "/api/v1/me", headers: bearer(token)

    assert_response :unauthorized
  end

  test "a user can be signed in on several devices at once" do
    first = login
    second = login

    [ first, second ].each do |token|
      get "/api/v1/me", headers: bearer(token)
      assert_response :success
    end
  end

  test "logout revokes only the token that was used" do
    phone = login
    tablet = login

    delete "/api/v1/auth/logout", headers: bearer(phone)
    assert_response :no_content

    get "/api/v1/me", headers: bearer(phone)
    assert_response :unauthorized
    get "/api/v1/me", headers: bearer(tablet)
    assert_response :success
  end

  test "logout requires a valid token" do
    delete "/api/v1/auth/logout"

    assert_response :unauthorized
  end

  test "only the newest tokens are kept per user" do
    tokens = (ApiToken::MAX_PER_USER + 2).times.map do |i|
      travel_to(i.seconds.from_now) { ApiToken.issue!(@user).last }
    end

    assert_equal ApiToken::MAX_PER_USER, @user.api_tokens.count
    get "/api/v1/me", headers: bearer(tokens.first)
    assert_response :unauthorized
    get "/api/v1/me", headers: bearer(tokens.last)
    assert_response :success
  end

  test "expired tokens are pruned when a new one is issued" do
    login
    ApiToken.update_all(expires_at: 1.day.ago)

    login

    assert_equal 1, @user.api_tokens.count
  end

  test "last use is recorded, but not on every request" do
    token = login
    record = ApiToken.find_by!(token_digest: ApiToken.digest(token))
    assert_nil record.last_used_at

    get "/api/v1/me", headers: bearer(token)
    first_use = record.reload.last_used_at
    assert first_use

    travel 10.minutes do
      get "/api/v1/me", headers: bearer(token)
    end
    assert_equal first_use, record.reload.last_used_at

    travel 2.hours do
      get "/api/v1/me", headers: bearer(token)
    end
    assert_operator record.reload.last_used_at, :>, first_use
  end

  test "repeated failed logins for one account are rate limited" do
    8.times do
      post "/api/v1/auth/login", params: { auth: { email: @user.email, password: "wrong" } }
      assert_response :unauthorized
    end

    post "/api/v1/auth/login", params: { auth: { email: @user.email, password: "password123" } }

    assert_response :too_many_requests
    assert response.headers["Retry-After"].present?
    assert_equal "too many login attempts, try again later", response.parsed_body["error"]
  end

  test "the account limit ignores case and does not affect other accounts" do
    8.times { post "/api/v1/auth/login", params: { auth: { email: @user.email.upcase, password: "wrong" } } }
    other = User.create!(organization: @organization, name: "Other", email: "other@example.com", password: "password123", role: "inspector")

    post "/api/v1/auth/login", params: { auth: { email: @user.email, password: "password123" } }
    assert_response :too_many_requests

    post "/api/v1/auth/login", params: { auth: { email: other.email, password: "password123" } }
    assert_response :success
  end

  test "one address cannot spray many accounts" do
    20.times { |i| post "/api/v1/auth/login", params: { auth: { email: "nobody#{i}@example.com", password: "x" } } }

    post "/api/v1/auth/login", params: { auth: { email: @user.email, password: "password123" } }

    assert_response :too_many_requests
  end

  private

  def login
    post "/api/v1/auth/login", params: { auth: { email: @user.email, password: "password123" } }
    assert_response :success
    response.parsed_body.fetch("token")
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
