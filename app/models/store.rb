class Store < ApplicationRecord
  has_many :products, dependent: :destroy
  
  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :url, format: { with: /\Ahttps?:\/\/smartstore\.naver\.com\/[\w-]+\z/,
                           message: "must be a valid Naver Smart Store URL" }
  
  enum :status, { pending: 'pending', scraping: 'scraping', completed: 'completed', failed: 'failed' }
  enum :business_type, { domestic: 'domestic', overseas: 'overseas', mixed: 'mixed' }
  
  scope :recent, -> { order(scraped_at: :desc) }
  scope :by_business_type, ->(type) { where(business_type: type) if type.present? }
  
  def needs_update?
    scraped_at.nil? || scraped_at < 24.hours.ago
  end
end
