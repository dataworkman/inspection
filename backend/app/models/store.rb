class Store < ApplicationRecord
  belongs_to :organization
  has_many :inspections, dependent: :restrict_with_exception
  has_many :corrective_actions, dependent: :restrict_with_exception

  validates :name, :store_code, presence: true
  validates :store_code, uniqueness: { scope: :organization_id }

  scope :active, -> { where(active: true) }

  def as_api_json
    {
      id: id,
      organization_id: organization_id,
      name: name,
      store_code: store_code,
      address: address,
      phone: phone,
      active: active
    }
  end
end
