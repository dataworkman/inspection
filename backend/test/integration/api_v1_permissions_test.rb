require "test_helper"

class ApiV1PermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Bakery Group A")
    @other_org = Organization.create!(name: "Bakery Group B")
    @admin = create_user(@org, "admin", "admin-a@example.com")
    @other_admin = create_user(@other_org, "admin", "admin-b@example.com")
    @inspector = create_user(@org, "inspector", "inspector-1@example.com")
    @other_inspector = create_user(@org, "inspector", "inspector-2@example.com")
    @manager = create_user(@org, "store_manager", "manager@example.com")

    @store = @org.stores.create!(name: "Downtown", store_code: "DT-1")
    @template = build_template(@org)
    @question = @template.inspection_questions.first
  end

  test "requests without a valid token get a JSON 401" do
    get "/api/v1/stores"

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert response.parsed_body["error"].present?

    get "/api/v1/stores", headers: auth_headers("not-a-real-token")
    assert_response :unauthorized
  end

  test "deactivated users cannot log in and lose access with an existing token" do
    token = login(@inspector)
    @inspector.update!(active: false)

    get "/api/v1/stores", headers: auth_headers(token)
    assert_response :unauthorized

    post "/api/v1/auth/login", params: { auth: { email: @inspector.email, password: "password123" } }
    assert_response :unauthorized
    assert_equal "account is deactivated", response.parsed_body["error"]
  end

  test "users without an organization are rejected" do
    orphan = User.create!(name: "Orphan", email: "orphan@example.com", password: "password123", role: "admin")
    Store.create!(name: "Orphan Store", store_code: "OR-1")

    get "/api/v1/stores", headers: auth_headers(login(orphan))

    assert_response :forbidden
  end

  test "an admin of another organization cannot see or change an inspection" do
    inspection_id, response_id = start_inspection(login(@inspector))
    other_token = login(@other_admin)

    get "/api/v1/inspections/#{inspection_id}", headers: auth_headers(other_token)
    assert_response :not_found

    patch "/api/v1/inspection_responses/#{response_id}",
      headers: auth_headers(other_token),
      params: { response: { score: 1, comment: "tampered" } }
    assert_response :not_found
    assert_nil InspectionResponse.find(response_id).comment
  end

  test "an inspector cannot change another inspector's responses or photos" do
    owner_token = login(@inspector)
    intruder_token = login(@other_inspector)
    inspection_id, response_id = start_inspection(owner_token)

    patch "/api/v1/inspection_responses/#{response_id}", headers: auth_headers(intruder_token), params: { response: { score: 2 } }
    assert_response :not_found

    post "/api/v1/inspection_responses/#{response_id}/photos", headers: auth_headers(intruder_token), params: photo_params
    assert_response :not_found

    post "/api/v1/inspection_responses/#{response_id}/photos", headers: auth_headers(owner_token), params: photo_params
    assert_response :created
    photo_id = response.parsed_body.dig("photo", "id")

    delete "/api/v1/inspection_photos/#{photo_id}", headers: auth_headers(intruder_token)
    assert_response :not_found
    assert InspectionPhoto.exists?(photo_id)
    assert_equal inspection_id, InspectionPhoto.find(photo_id).inspection_id
  end

  test "photos cannot be added or deleted once the inspection is submitted" do
    token = login(@inspector)
    inspection_id, response_id = start_inspection(token)
    answer(token, response_id, score: 4, comment: "ok")

    post "/api/v1/inspection_responses/#{response_id}/photos", headers: auth_headers(token), params: photo_params
    assert_response :created
    photo_id = response.parsed_body.dig("photo", "id")

    post "/api/v1/inspections/#{inspection_id}/submit", headers: auth_headers(token), params: { inspection: { comment: "done" } }
    assert_response :success

    delete "/api/v1/inspection_photos/#{photo_id}", headers: auth_headers(token)
    assert_response :conflict
    assert InspectionPhoto.exists?(photo_id)

    post "/api/v1/inspection_responses/#{response_id}/photos", headers: auth_headers(token), params: photo_params
    assert_response :conflict
  end

  test "the status cannot be set through the update endpoint" do
    token = login(@inspector)
    inspection_id, = start_inspection(token)

    patch "/api/v1/inspections/#{inspection_id}", headers: auth_headers(token), params: { inspection: { status: "submitted", general_comment: "hi" } }

    assert_response :success
    inspection = Inspection.find(inspection_id)
    assert_equal "in_progress", inspection.status
    assert_nil inspection.submitted_at
    assert_equal "hi", inspection.general_comment
  end

  test "a response cannot point at a question from another organization's template" do
    token = login(@inspector)
    inspection_id, = start_inspection(token)
    foreign_question = build_template(@other_org).inspection_questions.first

    post "/api/v1/inspections/#{inspection_id}/responses",
      headers: auth_headers(token),
      params: { response: { inspection_question_id: foreign_question.id, score: 3 } }

    assert_response :unprocessable_content
  end

  test "store managers cannot run inspections" do
    manager_token = login(@manager)

    post "/api/v1/inspections", headers: auth_headers(manager_token), params: { inspection: { store_id: @store.id, inspection_template_id: @template.id } }
    assert_response :forbidden

    inspection_id, response_id = start_inspection(login(@inspector))
    patch "/api/v1/inspection_responses/#{response_id}", headers: auth_headers(manager_token), params: { response: { score: 3 } }
    assert_response :forbidden

    post "/api/v1/corrective_actions",
      headers: auth_headers(manager_token),
      params: { corrective_action: { inspection_id: inspection_id, inspection_response_id: response_id, title: "x" } }
    assert_response :forbidden
  end

  test "store managers only see and progress corrective actions assigned to them" do
    inspector_token = login(@inspector)
    inspection_id, response_id = start_inspection(inspector_token)
    assigned_id = create_action(inspector_token, inspection_id, response_id, assigned_to_id: @manager.id)
    unassigned_id = create_action(inspector_token, inspection_id, response_id)
    manager_token = login(@manager)

    get "/api/v1/corrective_actions", headers: auth_headers(manager_token)
    assert_equal [ assigned_id ], response.parsed_body["corrective_actions"].pluck("id")

    patch "/api/v1/corrective_actions/#{unassigned_id}", headers: auth_headers(manager_token), params: { corrective_action: { status: "Resolved" } }
    assert_response :not_found

    patch "/api/v1/corrective_actions/#{assigned_id}", headers: auth_headers(manager_token), params: { corrective_action: { status: "Verified" } }
    assert_response :forbidden

    patch "/api/v1/corrective_actions/#{assigned_id}",
      headers: auth_headers(manager_token),
      params: { corrective_action: { status: "Resolved", title: "renamed", severity: "Low" } }
    assert_response :success
    action = CorrectiveAction.find(assigned_id)
    assert_equal "Resolved", action.status
    assert_not_equal "renamed", action.title
    assert_equal "High", action.severity
  end

  test "an inspector cannot update actions of inspections they cannot see" do
    inspection_id, response_id = start_inspection(login(@inspector))
    action_id = create_action(login(@inspector), inspection_id, response_id)

    patch "/api/v1/corrective_actions/#{action_id}",
      headers: auth_headers(login(@other_inspector)),
      params: { corrective_action: { status: "Resolved" } }
    assert_response :not_found

    patch "/api/v1/corrective_actions/#{action_id}",
      headers: auth_headers(login(@admin)),
      params: { corrective_action: { status: "Verified" } }
    assert_response :success
  end

  test "corrective actions cannot be assigned to users of another organization" do
    token = login(@inspector)
    inspection_id, response_id = start_inspection(token)

    post "/api/v1/corrective_actions",
      headers: auth_headers(token),
      params: { corrective_action: { inspection_id: inspection_id, inspection_response_id: response_id, title: "x", assigned_to_id: @other_admin.id } }

    assert_response :unprocessable_content
    assert_match(/same organization/, response.parsed_body["error"])
    assert_not_includes response.body, @other_admin.email
  end

  test "corrective actions identify their inspection and response and track completion" do
    token = login(@inspector)
    inspection_id, response_id = start_inspection(token)
    action_id = create_action(token, inspection_id, response_id)

    assert_equal [ inspection_id, response_id ], response.parsed_body["corrective_action"].values_at("inspection_id", "inspection_response_id")
    assert_nil response.parsed_body.dig("corrective_action", "completed_at")

    patch "/api/v1/corrective_actions/#{action_id}", headers: auth_headers(token), params: { corrective_action: { status: "Resolved" } }
    assert response.parsed_body.dig("corrective_action", "completed_at").present?

    patch "/api/v1/corrective_actions/#{action_id}", headers: auth_headers(token), params: { corrective_action: { status: "In Progress" } }
    assert_nil response.parsed_body.dig("corrective_action", "completed_at")
  end

  private

  def create_user(organization, role, email)
    User.create!(organization: organization, name: email, email: email, password: "password123", role: role)
  end

  def build_template(organization)
    template = organization.inspection_templates.create!(name: "Standard")
    category = template.inspection_categories.create!(name: "Cleanliness", weight: 100, position: 1)
    category.inspection_questions.create!(title: "Floors", max_score: 5, weight: 1, position: 1, photo_required: true, comment_required: true)
    template
  end

  def login(user)
    post "/api/v1/auth/login", params: { auth: { email: user.email, password: "password123" } }
    response.parsed_body.fetch("token")
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def start_inspection(token)
    post "/api/v1/inspections", headers: auth_headers(token), params: { inspection: { store_id: @store.id, inspection_template_id: @template.id } }
    assert_response :created
    inspection = response.parsed_body.fetch("inspection")
    [ inspection.fetch("id"), inspection.fetch("responses").first.fetch("id") ]
  end

  def answer(token, response_id, score:, comment: nil)
    patch "/api/v1/inspection_responses/#{response_id}", headers: auth_headers(token), params: { response: { score: score, comment: comment } }
    assert_response :success
  end

  def create_action(token, inspection_id, response_id, assigned_to_id: nil)
    post "/api/v1/corrective_actions",
      headers: auth_headers(token),
      params: { corrective_action: { inspection_id: inspection_id, inspection_response_id: response_id, title: "Fix it", severity: "High", assigned_to_id: assigned_to_id } }
    assert_response :created
    response.parsed_body.dig("corrective_action", "id")
  end

  def photo_params
    { photo: { comment: "evidence", annotation_data: "{}", original_image: fixture_file_upload("sample.jpg", "image/jpeg") } }
  end
end
