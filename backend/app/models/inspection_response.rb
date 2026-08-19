class InspectionResponse < ApplicationRecord
  belongs_to :inspection
  belongs_to :checklist_item

  has_many :inspection_photos, dependent: :nullify

  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :checklist_item_id, uniqueness: { scope: :inspection_id }

  after_save :recalculate_inspection_score

  def as_api_json
    {
      id: id,
      checklist_item_id: checklist_item_id,
      category: checklist_item.category,
      title: checklist_item.title,
      weight: checklist_item.weight,
      score: score,
      passed: passed,
      comment: comment,
      photos: inspection_photos.map(&:as_api_json)
    }
  end

  private

  def recalculate_inspection_score
    inspection.recalculate_score!
  end
end
