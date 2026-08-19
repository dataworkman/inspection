require "test_helper"

class ApiV1WorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "Admin", email: "admin@example.com", password: "password123", role: "admin")
    @inspector = User.create!(name: "Inspector", email: "inspector@example.com", password: "password123", role: "inspector")
    @store = Store.create!(name: "Test Store", code: "T-1", address: "1 Test Way")
    @template = ChecklistTemplate.create!(title: "Daily")
    @item = ChecklistItem.create!(checklist_template: @template, category: "Safety", title: "Cooler temp logged", weight: 2, position: 1)
  end

  test "login through inspection submission and dashboard" do
    post "/api/v1/auth/login", params: { auth: { email: @inspector.email, password: "password123" } }
    assert_response :success
    token = response.parsed_body.fetch("token")

    get "/api/v1/stores", headers: auth_headers(token)
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("stores").size

    post "/api/v1/stores/#{@store.id}/inspections", headers: auth_headers(token)
    assert_response :created
    inspection = response.parsed_body.fetch("inspection")
    inspection_id = inspection.fetch("id")
    response_id = inspection.fetch("responses").first.fetch("id")

    get "/api/v1/inspections/#{inspection_id}/checklist", headers: auth_headers(token)
    assert_response :success
    assert_equal "Cooler temp logged", response.parsed_body.dig("checklist", "items", 0, "title")

    patch "/api/v1/inspections/#{inspection_id}/responses/#{response_id}",
      headers: auth_headers(token),
      params: { response: { score: 90, passed: true, comment: "Logged at opening." } }
    assert_response :success

    post "/api/v1/inspections/#{inspection_id}/photos",
      headers: auth_headers(token),
      params: {
        photo: {
          inspection_response_id: response_id,
          comment: "Thermometer reading",
          annotation_json: { marks: [] }.to_json,
          image: fixture_file_upload("sample.jpg", "image/jpeg")
        }
      }
    assert_response :created

    patch "/api/v1/inspections/#{inspection_id}", headers: auth_headers(token), params: { inspection: { comment: "Ready to submit." } }
    assert_response :success

    post "/api/v1/inspections/#{inspection_id}/submit", headers: auth_headers(token), params: { inspection: { comment: "Complete." } }
    assert_response :success
    assert_equal "submitted", response.parsed_body.dig("inspection", "status")
    assert_equal 90.0, response.parsed_body.dig("inspection", "score")

    get "/api/v1/inspections", headers: auth_headers(token)
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("inspections").size

    post "/api/v1/auth/login", params: { auth: { email: @admin.email, password: "password123" } }
    admin_token = response.parsed_body.fetch("token")

    get "/api/v1/dashboard", headers: auth_headers(admin_token)
    assert_response :success
    assert_equal 1, response.parsed_body.dig("dashboard", "submitted_inspections")
  end

  private

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
