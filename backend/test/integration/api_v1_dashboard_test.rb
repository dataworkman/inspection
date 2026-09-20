require "test_helper"

class ApiV1DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Dashboard Group")
    @other_org = Organization.create!(name: "Other Group")
    @admin = User.create!(organization: @org, name: "Admin", email: "dash-admin@example.com", password: "password123", role: "admin")
    @inspector = User.create!(organization: @org, name: "Inspector", email: "dash-inspector@example.com", password: "password123", role: "inspector")
    @token = login(@admin)
  end

  test "only admins can see the dashboard" do
    get "/api/v1/dashboard", headers: bearer(login(@inspector))

    assert_response :forbidden
  end

  test "a store's latest score follows when it was submitted, not when it was started" do
    store = make_store("Downtown")
    # Started long ago but submitted today, versus started later but submitted earlier.
    submit_inspection(store, score: 90, created_at: 20.days.ago, submitted_at: 1.hour.ago)
    submit_inspection(store, score: 50, created_at: 2.days.ago, submitted_at: 5.days.ago)

    row = ranking_row("Downtown")

    assert_equal 90.0, row["latest_score"]
    assert_equal 50.0, row["previous_score"]
    assert_equal 70.0, row["average_score"]
    assert_equal [ 90.0, 50.0 ], row["score_trend"].pluck("score")
  end

  test "stores below standard are counted by their latest score, not their worst ever" do
    improved = make_store("Improved")
    submit_inspection(improved, score: 40, submitted_at: 10.days.ago)
    submit_inspection(improved, score: 90, submitted_at: 1.day.ago)
    struggling = make_store("Struggling")
    submit_inspection(struggling, score: 90, submitted_at: 10.days.ago)
    submit_inspection(struggling, score: 60, submitted_at: 1.day.ago)
    make_store("Never inspected")

    assert_equal 1, dashboard["stores_below_standard"]
  end

  test "the ranking lists the best store first and uninspected stores last" do
    submit_inspection(make_store("Middle"), score: 75)
    submit_inspection(make_store("Best"), score: 95)
    submit_inspection(make_store("Worst"), score: 55)
    make_store("Aardvark, not inspected")

    names = dashboard["store_ranking"].map { |row| row.dig("store", "name") }

    assert_equal [ "Best", "Middle", "Worst", "Aardvark, not inspected" ], names
  end

  test "stores that need attention are flagged for each reason" do
    low = make_store("Low score")
    submit_inspection(low, score: 65)

    drop = make_store("Sharp drop")
    submit_inspection(drop, score: 95, submitted_at: 10.days.ago)
    submit_inspection(drop, score: 84, submitted_at: 1.day.ago)

    critical = make_store("Critical action")
    submit_inspection(critical, score: 90)
    add_action(critical, severity: "Critical")

    overdue = make_store("Overdue action")
    submit_inspection(overdue, score: 90)
    add_action(overdue, due_date: 3.days.ago.to_date)

    fine = make_store("Fine")
    submit_inspection(fine, score: 90, submitted_at: 10.days.ago)
    submit_inspection(fine, score: 85, submitted_at: 1.day.ago)
    add_action(fine, severity: "Low", due_date: 3.days.from_now.to_date)

    closed = make_store("Closed issues")
    submit_inspection(closed, score: 90)
    add_action(closed, severity: "Critical", status: "Resolved", due_date: 3.days.ago.to_date)

    flagged = dashboard["attention_required"].map { |row| row.dig("store", "name") }

    assert_equal [ "Critical action", "Low score", "Overdue action", "Sharp drop" ], flagged.sort
  end

  test "each flagged store says why" do
    low = make_store("Low score")
    submit_inspection(low, score: 65)
    both = make_store("Both")
    submit_inspection(both, score: 60)
    add_action(both, severity: "Critical", due_date: 2.days.ago.to_date)
    drop = make_store("Sharp drop")
    submit_inspection(drop, score: 95, submitted_at: 10.days.ago)
    submit_inspection(drop, score: 84, submitted_at: 1.day.ago)
    make_store("Fine")

    reasons = dashboard["store_ranking"].to_h { |row| [ row.dig("store", "name"), row["attention_reasons"] ] }

    assert_equal [ "low_score" ], reasons["Low score"]
    assert_equal [ "critical_action", "low_score", "overdue_action" ], reasons["Both"]
    assert_equal [ "score_drop" ], reasons["Sharp drop"]
    assert_equal [], reasons["Fine"]
  end

  test "open and critical action counts are reported per store and overall" do
    store = make_store("Busy")
    submit_inspection(store, score: 90)
    add_action(store, severity: "Critical")
    add_action(store, severity: "High")
    add_action(store, severity: "Critical", status: "Verified")

    row = ranking_row("Busy")

    assert_equal [ 2, 1 ], row.values_at("open_issues", "critical_issues")
    assert_equal [ 2, 1 ], dashboard.values_at("open_corrective_actions", "critical_corrective_actions")
  end

  test "recent inspections are the most recently submitted" do
    store = make_store("Recent")
    submit_inspection(store, score: 70, created_at: 1.day.ago, submitted_at: 6.days.ago)
    newest = submit_inspection(store, score: 80, created_at: 30.days.ago, submitted_at: 1.hour.ago)

    assert_equal newest.id, dashboard["recent_inspections"].first["id"]
  end

  test "other organizations' data and inactive stores are left out" do
    submit_inspection(make_store("Mine"), score: 80)
    other_store = @other_org.stores.create!(name: "Theirs", store_code: "TH-1")
    other_user = User.create!(organization: @other_org, name: "O", email: "o@example.com", password: "password123", role: "admin")
    Inspection.create!(organization: @other_org, store: other_store, user: other_user, inspector: other_user, status: "submitted", total_score: 10, score: 10, submitted_at: Time.current)
    @org.stores.create!(name: "Closed", store_code: "CL-1", active: false)

    data = dashboard

    assert_equal 1, data["total_stores"]
    assert_equal 1, data["submitted_inspections"]
    assert_equal [ "Mine" ], data["store_ranking"].map { |row| row.dig("store", "name") }
  end

  test "an organization without inspections still renders" do
    make_store("Empty")

    data = dashboard

    assert_nil data["average_inspection_score"]
    assert_equal 0, data["stores_below_standard"]
    assert_empty data["recent_inspections"]
  end

  test "the number of queries does not grow with the number of stores" do
    counts = [ 1, 25 ].map do |stores|
      (stores - @org.stores.count).times do |i|
        store = make_store("Store #{@org.stores.count + i}")
        3.times { |n| submit_inspection(store, score: 60 + n * 10, submitted_at: (n + 1).days.ago) }
        add_action(store, severity: "High")
      end
      count_queries { get "/api/v1/dashboard", headers: bearer(@token) }
    end

    assert_operator counts.last, :<=, counts.first + 2, "queries grew from #{counts.first} to #{counts.last}"
    assert_operator counts.last, :<, 25
  end

  private

  def make_store(name)
    @org.stores.create!(name: name, store_code: "S-#{@org.stores.count + 1}-#{SecureRandom.hex(2)}")
  end

  def submit_inspection(store, score:, created_at: nil, submitted_at: Time.current)
    Inspection.create!(
      organization: @org, store: store, user: @inspector, inspector: @inspector, status: "submitted",
      total_score: score, score: score, submitted_at: submitted_at, created_at: created_at || submitted_at - 1.hour
    )
  end

  def add_action(store, severity: "Medium", status: "Open", due_date: nil)
    inspection = store.inspections.first || submit_inspection(store, score: 80)
    template = @org.inspection_templates.first || @org.inspection_templates.create!(name: "T")
    category = template.inspection_categories.first || template.inspection_categories.create!(name: "C", weight: 1)
    question = category.inspection_questions.first || category.inspection_questions.create!(title: "Q", max_score: 5, weight: 1)
    # Creating a response recalculates the inspection's score; keep the one the test set.
    score = inspection.total_score
    response = inspection.inspection_responses.first || inspection.inspection_responses.create!(inspection_question: question)
    inspection.update_columns(total_score: score, score: score)
    @org.corrective_actions.create!(
      store: store, inspection: inspection, inspection_response: response,
      title: "Fix", severity: severity, status: status, due_date: due_date
    )
  end

  def dashboard
    get "/api/v1/dashboard", headers: bearer(@token)
    assert_response :success
    response.parsed_body.fetch("dashboard")
  end

  def ranking_row(store_name)
    dashboard["store_ranking"].find { |row| row.dig("store", "name") == store_name }
  end

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql] =~ /SAVEPOINT|TRANSACTION/i }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def login(user)
    post "/api/v1/auth/login", params: { auth: { email: user.email, password: "password123" } }
    response.parsed_body.fetch("token")
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
