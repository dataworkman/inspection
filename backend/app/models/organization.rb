class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_exception
  has_many :stores, dependent: :restrict_with_exception
  has_many :inspection_templates, dependent: :restrict_with_exception
  has_many :inspections, dependent: :restrict_with_exception
  has_many :corrective_actions, dependent: :restrict_with_exception

  validates :name, presence: true
end
