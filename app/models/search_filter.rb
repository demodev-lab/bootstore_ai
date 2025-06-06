class SearchFilter < ApplicationRecord
  validates :name, presence: true
  validates :filter_type, presence: true
  validates :value, presence: true
  
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(filter_type: type) if type.present? }
  
  FILTER_TYPES = %w[business_type price_range category keyword_exclude].freeze
  
  validates :filter_type, inclusion: { in: FILTER_TYPES }
end
