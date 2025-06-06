class Product < ApplicationRecord
  belongs_to :store
  
  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :product_url, presence: true, uniqueness: true
  
  scope :by_price_range, ->(min, max) { where(price: min..max) if min && max }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :recent, -> { order(created_at: :desc) }
end
