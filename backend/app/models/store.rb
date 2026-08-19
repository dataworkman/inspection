class Store < ApplicationRecord
  has_many :inspections, dependent: :restrict_with_exception

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  scope :active, -> { where(active: true) }

  def as_api_json
    { id: id, name: name, code: code, address: address, active: active }
  end
end
