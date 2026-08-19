class ChecklistItem < ApplicationRecord
  belongs_to :checklist_template

  has_many :inspection_responses, dependent: :restrict_with_exception

  validates :category, :title, presence: true
  validates :weight, numericality: { greater_than: 0 }

  def as_api_json
    { id: id, category: category, title: title, weight: weight, position: position }
  end
end
