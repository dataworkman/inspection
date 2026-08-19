class ChecklistTemplate < ApplicationRecord
  has_many :checklist_items, -> { order(:position, :id) }, dependent: :destroy

  validates :title, presence: true

  scope :active, -> { where(active: true) }
end
