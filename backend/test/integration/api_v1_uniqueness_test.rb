require "test_helper"

# Makes the next save lose a race: a competing row is committed just before this
# record is written, and the uniqueness validation is skipped because in a real
# race it would run before the other request's INSERT and pass.
module InsertRaceSimulation
  mattr_accessor :pending, default: nil

  def save!(*args, **options)
    if (competing_row = InsertRaceSimulation.pending)
      InsertRaceSimulation.pending = nil
      self.class.insert!(competing_row.call(self))
      options[:validate] = false
    end
    super(*args, **options)
  end
end
InspectionResponse.prepend(InsertRaceSimulation)
Store.prepend(InsertRaceSimulation)

class ApiV1UniquenessTest < ActionDispatch::IntegrationTest
  teardown { InsertRaceSimulation.pending = nil }

  setup do
    @organization = Organization.create!(name: "Race Group")
    @admin = User.create!(organization: @organization, name: "Admin", email: "race-admin@example.com", password: "password123", role: "admin")
    @inspector = User.create!(organization: @organization, name: "Inspector", email: "race-inspector@example.com", password: "password123", role: "inspector")
    @store = @organization.stores.create!(name: "Race Store", store_code: "RS-1")
    @template = @organization.inspection_templates.create!(name: "Race Template")
    category = @template.inspection_categories.create!(name: "Cleanliness", weight: 100, position: 1)
    @question = category.inspection_questions.create!(title: "Floors", max_score: 5, weight: 1, position: 1)
  end

  test "creating a response that a concurrent request just created updates it instead of failing" do
    token = login(@inspector)
    inspection = start_inspection(token)
    inspection.inspection_responses.where(inspection_question_id: @question.id).delete_all
    InsertRaceSimulation.pending = lambda { |record|
      { inspection_id: record.inspection_id, inspection_question_id: record.inspection_question_id, score: 1, created_at: Time.current, updated_at: Time.current }
    }

    post "/api/v1/inspections/#{inspection.id}/responses",
      headers: auth_headers(token),
      params: { response: { inspection_question_id: @question.id, score: 3 } }

    assert_response :created
    rows = inspection.inspection_responses.where(inspection_question_id: @question.id)
    assert_equal 1, rows.count
    assert_equal 3, rows.first.score
  end

  test "a store code taken by a concurrent request is reported as a conflict" do
    token = login(@admin)
    InsertRaceSimulation.pending = lambda { |record|
      { organization_id: record.organization_id, name: "Winner", store_code: record.store_code, active: true, created_at: Time.current, updated_at: Time.current }
    }

    post "/api/v1/stores", headers: auth_headers(token), params: { store: { name: "Loser", store_code: "NEW-1" } }

    assert_response :conflict
    assert_equal "already exists", response.parsed_body["error"]
    assert_not Store.exists?(name: "Loser")
  end

  test "the database rejects a second response for the same question" do
    inspection = start_inspection(login(@inspector))

    assert_raises(ActiveRecord::RecordNotUnique) do
      inspection.inspection_responses.new(inspection_question: @question).save!(validate: false)
    end
  end

  test "store codes are unique per organization, not globally" do
    other = Organization.create!(name: "Other Group")

    assert_nothing_raised { other.stores.create!(name: "Same Code", store_code: "RS-1") }
    assert_raises(ActiveRecord::RecordNotUnique) do
      @organization.stores.new(name: "Dup", store_code: "RS-1").save!(validate: false)
    end
  end

  private

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
    Inspection.find(response.parsed_body.dig("inspection", "id"))
  end
end
