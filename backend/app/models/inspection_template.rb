class InspectionTemplate < ApplicationRecord
  belongs_to :organization
  has_many :inspection_categories, -> { order(:position, :id) }, dependent: :destroy
  has_many :inspection_questions, through: :inspection_categories

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  CATEGORY_ATTRIBUTES = %w[name weight position].freeze
  QUESTION_ATTRIBUTES = %w[title description max_score weight required photo_required comment_required position].freeze

  # Once an inspection has been started from a template, its questions, weights
  # and max scores define how that inspection is scored and read back, so they
  # must not change under it.
  def used?
    Inspection.exists?(inspection_template_id: id)
  end

  # Adds/updates categories and questions in place. Ids must belong to this
  # template (RecordNotFound otherwise). When editing a copy, [category_ids] and
  # [question_ids] translate the ids the client knows (from the original) to the
  # copy's.
  def apply_categories!(categories_params, category_ids: nil, question_ids: nil)
    categories_params.each do |category_params|
      category = find_or_build(inspection_categories, category_params[:id], category_ids)
      category.assign_attributes(category_params.except(:id, :questions))
      category.save!

      Array(category_params[:questions]).each do |question_params|
        question = find_or_build(category.inspection_questions, question_params[:id], question_ids)
        question.assign_attributes(question_params.except(:id))
        question.save!
      end
    end
  end

  # Copies this template into version + 1 (categories and questions included),
  # deactivates this one, and applies the requested edits to the copy.
  def create_next_version!(attributes, categories_params)
    transaction do
      successor = organization.inspection_templates.create!(
        attributes.except(:version).reverse_merge(name: name, description: description, active: true).merge(version: version + 1)
      )
      category_ids = {}
      question_ids = {}
      inspection_categories.includes(:inspection_questions).each do |category|
        category_copy = successor.inspection_categories.create!(category.slice(*CATEGORY_ATTRIBUTES))
        category_ids[category.id.to_s] = category_copy.id
        category.inspection_questions.each do |question|
          question_ids[question.id.to_s] = category_copy.inspection_questions.create!(question.slice(*QUESTION_ATTRIBUTES)).id
        end
      end

      update!(active: false)
      successor.apply_categories!(categories_params, category_ids: category_ids, question_ids: question_ids)
      successor
    end
  end

  def as_api_json(include_questions: false)
    payload = {
      id: id,
      organization_id: organization_id,
      name: name,
      description: description,
      version: version,
      active: active
    }
    payload[:categories] = inspection_categories.map { |category| category.as_api_json(include_questions: true) } if include_questions
    payload
  end

  private

  def find_or_build(scope, id, id_map)
    return scope.build if id.blank?

    id = id_map.fetch(id.to_s) { raise ActiveRecord::RecordNotFound } if id_map
    scope.find(id)
  end
end
