require "test_helper"

class ApiV1WorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @organization = Organization.create!(name: "Demo Bakery Group")
    @admin = User.create!(organization: @organization, name: "Admin", email: "admin@example.com", password: "password123", role: "admin")
    @inspector = User.create!(organization: @organization, name: "Inspector", email: "inspector@example.com", password: "password123", role: "inspector")
    @store = @organization.stores.create!(name: "Test Bakery", store_code: "T-1", address: "1 Test Way")
  end

  test "admin and inspector complete full MVP workflow" do
    admin_token = login(@admin.email)

    post "/api/v1/stores",
      headers: auth_headers(admin_token),
      params: { store: { name: "Created Bakery", store_code: "NEW-1", address: "2 Test Way", phone: "555-0000" } }
    assert_response :created

    post "/api/v1/inspection_templates",
      headers: auth_headers(admin_token),
      params: template_payload
    assert_response :created
    template_id = response.parsed_body.dig("inspection_template", "id")
    question_id = response.parsed_body.dig("inspection_template", "categories", 0, "questions", 0, "id")

    inspector_token = login(@inspector.email)

    get "/api/v1/stores", headers: auth_headers(inspector_token)
    assert_response :success

    post "/api/v1/inspections",
      headers: auth_headers(inspector_token),
      params: { inspection: { store_id: @store.id, inspection_template_id: template_id } }
    assert_response :created
    inspection = response.parsed_body.fetch("inspection")
    inspection_id = inspection.fetch("id")
    response_id = inspection.fetch("responses").first.fetch("id")

    patch "/api/v1/inspection_responses/#{response_id}",
      headers: auth_headers(inspector_token),
      params: { response: { inspection_question_id: question_id, score: 4, not_applicable: false, comment: "Good condition." } }
    assert_response :success

    post "/api/v1/inspection_responses/#{response_id}/photos",
      headers: auth_headers(inspector_token),
      params: {
        photo: {
          comment: "Annotated evidence",
          annotation_data: { tools: [ "freehand", "arrow", "text" ] }.to_json,
          original_image: fixture_file_upload("sample.jpg", "image/jpeg"),
          annotated_image: fixture_file_upload("sample.jpg", "image/jpeg")
        }
      }
    assert_response :created

    post "/api/v1/corrective_actions",
      headers: auth_headers(inspector_token),
      params: {
        corrective_action: {
          inspection_id: inspection_id,
          inspection_response_id: response_id,
          title: "Repair display case seal",
          description: "Seal is damaged.",
          severity: "High",
          status: "Open",
          due_date: Date.current + 7.days
        }
      }
    assert_response :created
    action_id = response.parsed_body.dig("corrective_action", "id")

    patch "/api/v1/inspections/#{inspection_id}",
      headers: auth_headers(inspector_token),
      params: { inspection: { general_comment: "Inspection complete." } }
    assert_response :success

    post "/api/v1/inspections/#{inspection_id}/submit",
      headers: auth_headers(inspector_token),
      params: { inspection: { comment: "Submitted." } }
    assert_response :success
    assert_equal "submitted", response.parsed_body.dig("inspection", "status")
    assert_equal 80.0, response.parsed_body.dig("inspection", "score")

    get "/api/v1/dashboard", headers: auth_headers(admin_token)
    assert_response :success
    assert_equal 1, response.parsed_body.dig("dashboard", "open_corrective_actions")

    get "/api/v1/stores/#{@store.id}/inspection_history", headers: auth_headers(admin_token)
    assert_response :success
    assert_equal 80.0, response.parsed_body.fetch("latest_score")

    patch "/api/v1/corrective_actions/#{action_id}",
      headers: auth_headers(admin_token),
      params: { corrective_action: { status: "In Progress" } }
    assert_response :success
    assert_equal "In Progress", response.parsed_body.dig("corrective_action", "status")
  end

  private

  def login(email)
    post "/api/v1/auth/login", params: { auth: { email: email, password: "password123" } }
    assert_response :success
    response.parsed_body.fetch("token")
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def template_payload
    {
      inspection_template: {
        name: "Bakery Standard Inspection",
        description: "Test template",
        version: 1,
        active: true,
        categories: [
          {
            name: "Cleanliness",
            weight: 30,
            position: 1,
            questions: [
              {
                title: "Floor cleanliness",
                description: "Floors are clean.",
                max_score: 5,
                weight: 1,
                required: true,
                photo_required: true,
                comment_required: true,
                position: 1
              }
            ]
          }
        ]
      }
    }
  end
end
