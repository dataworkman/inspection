require "test_helper"

class InspectionTest < ActiveSupport::TestCase
  test "serializes responses by category and question position" do
    organization = Organization.create!(name: "Ordering Bakery Group")
    user = User.create!(
      organization: organization,
      name: "Inspector",
      email: "ordering-inspector@example.com",
      password: "password123",
      role: "inspector"
    )
    store = organization.stores.create!(name: "Ordering Store", store_code: "ORD-1", address: "1 Test Way")
    template = organization.inspection_templates.create!(name: "Ordering Template", version: 1, active: true)
    service = template.inspection_categories.create!(name: "Service", weight: 25, position: 2)
    cleanliness = template.inspection_categories.create!(name: "Cleanliness", weight: 30, position: 1)
    greeting = service.inspection_questions.create!(title: "Greeting", max_score: 5, weight: 1, position: 1)
    floors = cleanliness.inspection_questions.create!(title: "Floors", max_score: 5, weight: 1, position: 2)
    counters = cleanliness.inspection_questions.create!(title: "Counters", max_score: 5, weight: 1, position: 1)
    inspection = store.inspections.create!(
      organization: organization,
      inspection_template: template,
      user: user,
      inspector: user,
      status: "in_progress"
    )

    inspection.inspection_responses.create!(inspection_question: greeting, score: 1)
    inspection.inspection_responses.create!(inspection_question: floors, score: 1)
    inspection.inspection_responses.create!(inspection_question: counters, score: 1)

    serialized = inspection.as_api_json(include_detail: true).fetch(:responses)

    assert_equal [ "Cleanliness", "Cleanliness", "Service" ], serialized.pluck(:category)
    assert_equal [ "Counters", "Floors", "Greeting" ], serialized.pluck(:title)
    assert_equal [ 1, 1, 2 ], serialized.pluck(:category_position)
    assert_equal [ 1, 2, 1 ], serialized.pluck(:position)
  end
end
