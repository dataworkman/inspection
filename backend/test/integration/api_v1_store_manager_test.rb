require "test_helper"

class ApiV1StoreManagerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Manager Group")
    @other_org = Organization.create!(name: "Other Group")
    @store = @org.stores.create!(name: "Downtown", store_code: "DT-1")
    @other_store = @org.stores.create!(name: "Airport", store_code: "AP-1")
    @admin = make_user("admin", "admin@example.com")
    @inspector = make_user("inspector", "inspector@example.com")
    @manager = make_user("store_manager", "manager@example.com", store: @store)

    @template = @org.inspection_templates.create!(name: "T")
    @question = @template.inspection_categories.create!(name: "C", weight: 1).inspection_questions.create!(title: "Q", max_score: 5, weight: 1)

    @submitted = inspection_at(@store, "submitted", 80)
    @in_progress = inspection_at(@store, "in_progress", 0)
    @elsewhere = inspection_at(@other_store, "submitted", 60)
    @own_action = action_for(@submitted, severity: "High")
    @unassigned_own_action = action_for(@submitted, severity: "Low")
    @other_action = action_for(@elsewhere, severity: "Critical")

    @token = login(@manager)
  end

  test "a store manager must be tied to a store of their organization" do
    manager = User.new(organization: @org, name: "M", email: "m2@example.com", password: "password123", role: "store_manager")
    assert_not manager.valid?
    assert_includes manager.errors[:store], "must be set for a store manager"

    manager.store = @org.stores.create!(name: "Mine", store_code: "M-1")
    assert manager.valid?

    manager.store = @other_org.stores.create!(name: "Theirs", store_code: "TH-1")
    assert_not manager.valid?

    admin = User.new(organization: @org, name: "A", email: "a2@example.com", password: "password123", role: "admin")
    assert admin.valid?, "other roles do not need a store"
  end

  test "the manager sees only their own store" do
    get "/api/v1/stores", headers: bearer
    assert_equal [ "Downtown" ], response.parsed_body["stores"].pluck("name")

    get "/api/v1/stores/#{@store.id}", headers: bearer
    assert_response :success

    get "/api/v1/stores/#{@other_store.id}", headers: bearer
    assert_response :not_found
  end

  test "the manager can read their store's history and only theirs" do
    get "/api/v1/stores/#{@store.id}/inspection_history", headers: bearer
    assert_response :success
    assert_equal [ @submitted.id ], response.parsed_body["history"].pluck("id")
    assert_equal 80.0, response.parsed_body["latest_score"]

    get "/api/v1/stores/#{@other_store.id}/inspection_history", headers: bearer
    assert_response :not_found
  end

  test "the manager sees their store's submitted inspections, not drafts or other stores" do
    get "/api/v1/inspections", headers: bearer
    assert_equal [ @submitted.id ], response.parsed_body["inspections"].pluck("id")

    get "/api/v1/inspections/#{@submitted.id}", headers: bearer
    assert_response :success
    assert_equal 1, response.parsed_body.dig("inspection", "responses").size

    get "/api/v1/inspections/#{@in_progress.id}", headers: bearer
    assert_response :not_found
    get "/api/v1/inspections/#{@elsewhere.id}", headers: bearer
    assert_response :not_found
  end

  test "the manager still cannot change inspections or open the dashboard" do
    patch "/api/v1/inspections/#{@submitted.id}", headers: bearer, params: { inspection: { general_comment: "x" } }
    assert_response :forbidden
    post "/api/v1/inspections/#{@submitted.id}/submit", headers: bearer
    assert_response :forbidden
    get "/api/v1/dashboard", headers: bearer
    assert_response :forbidden
  end

  test "the manager sees every corrective action of their store and moves them along" do
    get "/api/v1/corrective_actions", headers: bearer
    assert_equal [ @own_action.id, @unassigned_own_action.id ].sort, response.parsed_body["corrective_actions"].pluck("id").sort

    patch "/api/v1/corrective_actions/#{@unassigned_own_action.id}", headers: bearer, params: { corrective_action: { status: "In Progress", title: "renamed" } }
    assert_response :success
    assert_equal "In Progress", @unassigned_own_action.reload.status
    assert_not_equal "renamed", @unassigned_own_action.title

    patch "/api/v1/corrective_actions/#{@own_action.id}", headers: bearer, params: { corrective_action: { status: "Verified" } }
    assert_response :forbidden

    patch "/api/v1/corrective_actions/#{@other_action.id}", headers: bearer, params: { corrective_action: { status: "Resolved" } }
    assert_response :not_found
  end

  test "a manager with no store assigned sees nothing" do
    @manager.update_columns(store_id: nil)

    get "/api/v1/stores", headers: bearer
    assert_empty response.parsed_body["stores"]
    get "/api/v1/inspections", headers: bearer
    assert_empty response.parsed_body["inspections"]
    get "/api/v1/corrective_actions", headers: bearer
    assert_empty response.parsed_body["corrective_actions"]
  end

  test "the current user reports their store" do
    get "/api/v1/me", headers: bearer

    assert_equal @store.id, response.parsed_body.dig("user", "store_id")
  end

  test "admins list their organization's users" do
    make_user("admin", "other-org-admin@example.com", org: @other_org)

    get "/api/v1/users", headers: bearer(login(@admin))

    assert_response :success
    emails = response.parsed_body["users"].pluck("email")
    assert_includes emails, "manager@example.com"
    assert_not_includes emails, "other-org-admin@example.com"
    manager = response.parsed_body["users"].find { |u| u["email"] == "manager@example.com" }
    assert_equal @store.id, manager["store_id"]
  end

  test "only admins manage users" do
    get "/api/v1/users", headers: bearer
    assert_response :forbidden

    patch "/api/v1/users/#{@manager.id}", headers: bearer, params: { user: { store_id: @other_store.id } }
    assert_response :forbidden
    assert_equal @store.id, @manager.reload.store_id
  end

  test "an admin moves a manager to another store and the scope follows" do
    patch "/api/v1/users/#{@manager.id}", headers: bearer(login(@admin)), params: { user: { store_id: @other_store.id } }
    assert_response :success

    get "/api/v1/stores", headers: bearer
    assert_equal [ "Airport" ], response.parsed_body["stores"].pluck("name")
    get "/api/v1/corrective_actions", headers: bearer
    assert_equal [ @other_action.id ], response.parsed_body["corrective_actions"].pluck("id")
  end

  test "an admin cannot assign a store of another organization" do
    foreign = @other_org.stores.create!(name: "Foreign", store_code: "FO-1")

    patch "/api/v1/users/#{@manager.id}", headers: bearer(login(@admin)), params: { user: { store_id: foreign.id } }

    assert_response :unprocessable_content
    assert_equal @store.id, @manager.reload.store_id
  end

  test "an admin can deactivate a user, but not themselves, and cannot change roles or emails" do
    admin_token = login(@admin)

    patch "/api/v1/users/#{@manager.id}", headers: bearer(admin_token), params: { user: { active: false, role: "admin", email: "evil@example.com" } }
    assert_response :success
    assert_not @manager.reload.active
    assert_equal "store_manager", @manager.role
    assert_equal "manager@example.com", @manager.email

    get "/api/v1/stores", headers: bearer
    assert_response :unauthorized

    patch "/api/v1/users/#{@admin.id}", headers: bearer(admin_token), params: { user: { active: false } }
    assert_response :unprocessable_content
    assert @admin.reload.active
  end

  test "users of other organizations cannot be reached" do
    stranger = make_user("inspector", "stranger@example.com", org: @other_org)

    patch "/api/v1/users/#{stranger.id}", headers: bearer(login(@admin)), params: { user: { active: false } }

    assert_response :not_found
    assert stranger.reload.active
  end

  private

  def make_user(role, email, org: @org, store: nil)
    User.create!(organization: org, name: email, email: email, password: "password123", role: role, store: store)
  end

  def inspection_at(store, status, score)
    inspection = Inspection.create!(
      organization: @org, store: store, inspection_template: @template, user: @inspector, inspector: @inspector,
      status: status, total_score: score, score: score, submitted_at: (Time.current if status == "submitted")
    )
    inspection.inspection_responses.create!(inspection_question: @question)
    inspection.update_columns(total_score: score, score: score)
    inspection
  end

  def action_for(inspection, severity:)
    @org.corrective_actions.create!(
      store: inspection.store, inspection: inspection, inspection_response: inspection.inspection_responses.first,
      title: "Fix", severity: severity
    )
  end

  def login(user)
    post "/api/v1/auth/login", params: { auth: { email: user.email, password: "password123" } }
    response.parsed_body.fetch("token")
  end

  def bearer(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end
end
