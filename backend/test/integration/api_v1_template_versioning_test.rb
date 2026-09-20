require "test_helper"

class ApiV1TemplateVersioningTest < ActionDispatch::IntegrationTest
  setup do
    @organization = Organization.create!(name: "Versioning Group")
    @admin = User.create!(organization: @organization, name: "Admin", email: "ver-admin@example.com", password: "password123", role: "admin")
    @inspector = User.create!(organization: @organization, name: "Inspector", email: "ver-inspector@example.com", password: "password123", role: "inspector")
    @store = @organization.stores.create!(name: "Store", store_code: "V-1")

    @template = @organization.inspection_templates.create!(name: "Standard", version: 1)
    @category = @template.inspection_categories.create!(name: "Cleanliness", weight: 60, position: 1)
    @floors = @category.inspection_questions.create!(title: "Floors", max_score: 5, weight: 1, position: 1)
    @counters = @category.inspection_questions.create!(title: "Counters", max_score: 5, weight: 1, position: 2)
    @admin_token = login(@admin)
  end

  test "a template nobody has used is edited in place" do
    patch "/api/v1/inspection_templates/#{@template.id}", headers: bearer(@admin_token), params: edit_floors(max_score: 10), as: :json

    assert_response :success
    assert_equal false, response.parsed_body["versioned"]
    assert_equal @template.id, response.parsed_body.dig("inspection_template", "id")
    assert_equal 1, response.parsed_body.dig("inspection_template", "version")
    assert_equal 10, @floors.reload.max_score
    assert_equal 1, InspectionTemplate.count
  end

  test "editing a template that inspections use creates a new version and leaves the old one untouched" do
    inspection = start_inspection
    score_before = inspection.reload.total_score

    patch "/api/v1/inspection_templates/#{@template.id}", headers: bearer(@admin_token), params: edit_floors(max_score: 10, weight: 3), as: :json

    assert_response :success
    assert_equal true, response.parsed_body["versioned"]
    successor = InspectionTemplate.find(response.parsed_body.dig("inspection_template", "id"))
    assert_not_equal @template.id, successor.id
    assert_equal 2, successor.version
    assert successor.active
    assert_not @template.reload.active

    # The original questions are exactly as the running inspection saw them.
    assert_equal [ 5, 1 ], [ @floors.reload.max_score, @floors.weight.to_i ]
    assert_equal score_before, inspection.reload.total_score
    assert_equal @template.id, inspection.inspection_template_id

    # The copy carries the edit and every untouched category/question.
    copied_floors = successor.inspection_questions.find_by!(title: "Floors")
    assert_equal [ 10, 3 ], [ copied_floors.max_score, copied_floors.weight.to_i ]
    assert_equal [ "Floors", "Counters" ], successor.inspection_questions.order(:position).pluck(:title)
    assert_equal [ successor.id ], successor.inspection_categories.pluck(:inspection_template_id).uniq
    assert_empty successor.inspection_questions.pluck(:id) & @template.inspection_questions.pluck(:id)
  end

  test "new inspections use the new version; running ones keep working on the old one" do
    running = start_inspection
    patch "/api/v1/inspection_templates/#{@template.id}", headers: bearer(@admin_token), params: edit_floors(max_score: 10), as: :json
    successor_id = response.parsed_body.dig("inspection_template", "id")

    get "/api/v1/inspection_templates", headers: bearer(@admin_token)
    assert_equal [ successor_id ], response.parsed_body["inspection_templates"].pluck("id")

    post "/api/v1/inspections",
      headers: bearer(login(@inspector)),
      params: { inspection: { store_id: @store.id, inspection_template_id: @template.id } }
    assert_response :not_found

    response_id = running.inspection_responses.first.id
    patch "/api/v1/inspection_responses/#{response_id}", headers: bearer(login(@inspector)), params: { response: { score: 4 } }
    assert_response :success
  end

  test "questions and categories can be added while versioning" do
    start_inspection

    patch "/api/v1/inspection_templates/#{@template.id}",
      headers: bearer(@admin_token),
      params: { inspection_template: { categories: [
        { id: @category.id, questions: [ { title: "Windows", max_score: 5, weight: 1, position: 3 } ] },
        { name: "Service", weight: 40, position: 2, questions: [ { title: "Greeting", max_score: 5, weight: 1, position: 1 } ] }
      ] } },
      as: :json

    assert_response :success
    successor = InspectionTemplate.find(response.parsed_body.dig("inspection_template", "id"))
    assert_equal [ "Floors", "Counters", "Windows", "Greeting" ], successor.inspection_questions.joins(:inspection_category).reorder("inspection_categories.position", "inspection_questions.position").pluck(:title)
    assert_equal 2, @template.reload.inspection_questions.count
  end

  test "metadata-only changes never create a version" do
    start_inspection

    patch "/api/v1/inspection_templates/#{@template.id}", headers: bearer(@admin_token), params: { inspection_template: { name: "Renamed", active: false } }, as: :json

    assert_response :success
    assert_equal false, response.parsed_body["versioned"]
    assert_equal "Renamed", @template.reload.name
    assert_not @template.active
    assert_equal 1, InspectionTemplate.count
  end

  test "ids that do not belong to the template are rejected without changing anything" do
    other_category = InspectionTemplate.create!(organization: @organization, name: "Other").inspection_categories.create!(name: "Other", weight: 1)
    templates_before = InspectionTemplate.count

    patch "/api/v1/inspection_templates/#{@template.id}",
      headers: bearer(@admin_token),
      params: { inspection_template: { categories: [ { id: other_category.id, name: "Hijacked" } ] } },
      as: :json

    assert_response :not_found
    assert_equal "Other", other_category.reload.name
    assert_equal templates_before, InspectionTemplate.count
  end

  test "an unknown id is rejected while versioning and the failed version is rolled back" do
    start_inspection
    templates_before = InspectionTemplate.count

    patch "/api/v1/inspection_templates/#{@template.id}",
      headers: bearer(@admin_token),
      params: { inspection_template: { categories: [ { id: 999_999, name: "Ghost" } ] } },
      as: :json

    assert_response :not_found
    assert_equal templates_before, InspectionTemplate.count
    assert @template.reload.active
  end

  test "only admins can change templates" do
    patch "/api/v1/inspection_templates/#{@template.id}", headers: bearer(login(@inspector)), params: edit_floors(max_score: 10), as: :json

    assert_response :forbidden
    assert_equal 5, @floors.reload.max_score
  end

  private

  def edit_floors(**attributes)
    { inspection_template: { categories: [ { id: @category.id, questions: [ { id: @floors.id, **attributes } ] } ] } }
  end

  def start_inspection
    post "/api/v1/inspections",
      headers: bearer(login(@inspector)),
      params: { inspection: { store_id: @store.id, inspection_template_id: @template.id } }
    assert_response :created
    Inspection.find(response.parsed_body.dig("inspection", "id"))
  end

  def login(user)
    post "/api/v1/auth/login", params: { auth: { email: user.email, password: "password123" } }
    response.parsed_body.fetch("token")
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
