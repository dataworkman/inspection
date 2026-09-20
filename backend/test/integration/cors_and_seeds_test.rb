require "test_helper"

class CorsAndSeedsTest < ActionDispatch::IntegrationTest
  test "origins default to everything outside production and to nothing in production" do
    assert_equal [ "*" ], CorsConfig.origins(nil, production: false)
    assert_equal [], CorsConfig.origins(nil, production: true)
    assert_equal [], CorsConfig.origins("  ", production: true)
  end

  test "configured origins are parsed and win in every environment" do
    configured = " https://a.example.com, https://b.example.com ,,"

    assert_equal [ "https://a.example.com", "https://b.example.com" ], CorsConfig.origins(configured, production: true)
    assert_equal [ "https://a.example.com", "https://b.example.com" ], CorsConfig.origins(configured, production: false)
  end

  test "preflight requests are answered outside production" do
    options "/api/v1/stores",
      headers: {
        "Origin" => "https://app.example.com",
        "Access-Control-Request-Method" => "GET",
        "Access-Control-Request-Headers" => "authorization"
      }

    assert_response :success
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "demo seed data is not created in production" do
    with_rails_env("production") do
      assert_output(/Skipping demo seed data in production/) { load Rails.root.join("db/seeds.rb") }
    end

    assert_equal 0, User.count
    assert_equal 0, Organization.count
  end

  test "demo seed data can be forced in production and is created elsewhere" do
    ENV["SEED_DEMO_DATA"] = "1"
    with_rails_env("production") do
      assert_output(/Seeded 1 organization/) { load Rails.root.join("db/seeds.rb") }
    end
    assert_equal 3, User.count
  ensure
    ENV.delete("SEED_DEMO_DATA")
  end

  test "demo seed data is created in development and test" do
    assert_output(/Seeded 1 organization/) { load Rails.root.join("db/seeds.rb") }

    assert_equal 3, User.count
  end

  private

  def with_rails_env(name)
    original = Rails.env.to_s
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end
end
