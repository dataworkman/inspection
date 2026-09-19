require "test_helper"

class InspectionScoringTest < ActiveSupport::TestCase
  setup do
    @organization = Organization.create!(name: "Scoring Group")
    @user = User.create!(organization: @organization, name: "Inspector", email: "scoring@example.com", password: "password123", role: "inspector")
    @store = @organization.stores.create!(name: "Scoring Store", store_code: "SC-1")
    @template = @organization.inspection_templates.create!(name: "Scoring Template")

    # One-question category and a four-question category with equal weights.
    small = @template.inspection_categories.create!(name: "Small", weight: 50, position: 1)
    big = @template.inspection_categories.create!(name: "Big", weight: 50, position: 2)
    @small_question = small.inspection_questions.create!(title: "Only", max_score: 5, weight: 1, position: 1)
    @big_questions = 4.times.map { |i| big.inspection_questions.create!(title: "Big #{i}", max_score: 5, weight: 1, position: i + 1) }

    @inspection = @store.inspections.create!(
      organization: @organization, inspection_template: @template, user: @user, inspector: @user, status: "in_progress"
    )
    @responses = (@big_questions + [ @small_question ]).to_h do |question|
      [ question, @inspection.inspection_responses.create!(inspection_question: question) ]
    end
  end

  test "category weights are shares of the total regardless of question count" do
    @responses[@small_question].update!(score: 5)
    @big_questions.each { |question| @responses[question].update!(score: 1) }

    assert_equal 60.0, @inspection.reload.total_score.to_f
  end

  test "question weights apply within a category" do
    heavy = @template.inspection_categories.first.inspection_questions.create!(title: "Heavy", max_score: 5, weight: 3, position: 2)
    @responses[@small_question].update!(score: 5)
    @inspection.inspection_responses.create!(inspection_question: heavy, score: 1)

    # (5*1 + 1*3) / (5*1 + 5*3) = 40%
    assert_equal 40.0, @inspection.reload.total_score.to_f
  end

  test "unanswered items are excluded instead of scoring zero" do
    @responses[@small_question].update!(score: 4)

    assert_equal 80.0, @inspection.reload.total_score.to_f
  end

  test "not applicable items and empty categories drop out of the score" do
    @responses[@small_question].update!(score: 2)
    @big_questions.each { |question| @responses[question].update!(not_applicable: true) }

    assert_equal 40.0, @inspection.reload.total_score.to_f
  end

  test "a score cannot exceed the question's max score" do
    response = @responses[@small_question]

    assert_not response.update(score: 6)
    assert_includes response.errors[:score], "must be at most 5"
    assert response.update(score: 5)
  end

  test "a response must use a question from the inspection's template" do
    other_template = @organization.inspection_templates.create!(name: "Other")
    other_question = other_template.inspection_categories.create!(name: "Other", weight: 1).inspection_questions.create!(title: "Other", max_score: 5, weight: 1)

    response = @inspection.inspection_responses.new(inspection_question: other_question, score: 3)

    assert_not response.valid?
    assert_includes response.errors[:inspection_question], "does not belong to this inspection's template"
  end

  test "submit is blocked until required items, photos and comments are provided" do
    @small_question.update!(photo_required: true, comment_required: true)

    error = assert_raises(ActiveRecord::RecordInvalid) { @inspection.submit! }
    assert_match(/Answer required items: Big 0, Big 1, Big 2, Big 3, Only/, error.message)
    assert_match(/Photo required for: Only/, error.message)
    assert_match(/Comment required for: Only/, error.message)
    assert_equal "in_progress", @inspection.reload.status
  end

  test "required-item summaries are truncated after five titles" do
    category = @template.inspection_categories.find_by!(name: "Big")
    3.times do |i|
      question = category.inspection_questions.create!(title: "Extra #{i}", max_score: 5, weight: 1, position: 10 + i)
      @inspection.inspection_responses.create!(inspection_question: question)
    end

    error = assert_raises(ActiveRecord::RecordInvalid) { @inspection.submit! }

    assert_match(/Answer required items: .* and 3 more/, error.message)
  end

  test "submit succeeds when requirements are met, exempting not applicable items" do
    @small_question.update!(photo_required: true, comment_required: true)
    @big_questions.each { |question| @responses[question].update!(score: 5) }
    @responses[@small_question].update!(not_applicable: true)

    @inspection.submit!(final_comment: "done")

    assert_equal "submitted", @inspection.reload.status
    assert_equal 100.0, @inspection.total_score.to_f
    assert_not @inspection.editable?
  end

  test "optional questions may stay unanswered at submission" do
    @small_question.update!(required: false)
    @big_questions.each { |question| @responses[question].update!(score: 4) }

    @inspection.submit!

    assert_equal 80.0, @inspection.reload.total_score.to_f
  end
end
