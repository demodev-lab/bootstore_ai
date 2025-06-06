class Store < ApplicationRecord
  belongs_to :user
  has_many :products, dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :url, format: { with: /\Ahttps?:\/\/smartstore\.naver\.com\/[\w-]+\z/,
                           message: "must be a valid Naver Smart Store URL" }
  validates :follower_count, numericality: { greater_than_or_equal_to: 0 }
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  enum :status, { pending: 'pending', scraping: 'scraping', completed: 'completed', failed: 'failed' }
  enum :business_type, { domestic: 'domestic', overseas: 'overseas', mixed: 'mixed' }

  scope :recent, -> { order(scraped_at: :desc) }
  scope :by_business_type, ->(type) { where(business_type: type) if type.present? }
  scope :by_rating, ->(min_rating) { where('rating >= ?', min_rating) if min_rating.present? }
  scope :popular, -> { where('follower_count > ?', 1000) }
  scope :successful, -> { where(status: 'completed') }

  def needs_update?
    scraped_at.nil? || scraped_at < 24.hours.ago
  end

  def display_follower_count
    return '0' if follower_count.zero?

    if follower_count >= 1000000
      "#{(follower_count / 1000000.0).round(1)}M"
    elsif follower_count >= 1000
      "#{(follower_count / 1000.0).round(1)}K"
    else
      follower_count.to_s
    end
  end

  def average_discount_rate
    return 0 if products.empty?

    discounted_products = products.where('discount_rate > 0')
    return 0 if discounted_products.empty?

    (discounted_products.average(:discount_rate) || 0).round(1)
  end

  def total_reviews
    products.sum(:review_count)
  end

  def price_range
    return [0, 0] if products.empty?

    [products.minimum(:price) || 0, products.maximum(:price) || 0]
  end

  def popular_categories
    products.group(:category)
            .order('count_all DESC')
            .limit(5)
            .count
  end
end
