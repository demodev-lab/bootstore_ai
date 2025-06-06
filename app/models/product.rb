class Product < ApplicationRecord
  belongs_to :store

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :product_url, presence: true, uniqueness: { scope: :store_id }
  validates :review_count, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :by_price_range, ->(min, max) { where(price: min..max) if min && max }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { where('review_count > ?', 100) }
  scope :on_sale, -> { where('discount_rate > 0') }
  scope :high_rated, -> { where('review_count > ?', 50) }
  scope :recently_scraped, -> { where('scraped_at > ?', 1.week.ago) }

  def display_price
    "#{price.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}원"
  end

  def display_discount_rate
    return '' if discount_rate.zero?
    "#{discount_rate}% 할인"
  end

  def display_review_count
    return '리뷰 없음' if review_count.zero?

    if review_count >= 1000
      "리뷰 #{(review_count / 1000.0).round(1)}K"
    else
      "리뷰 #{review_count}"
    end
  end

  def discounted_price
    return price if discount_rate.zero?

    (price * (100 - discount_rate) / 100.0).round(0)
  end

  def is_popular?
    review_count > 100
  end

  def is_on_sale?
    discount_rate > 0
  end

  def freshness_score
    return 0 unless scraped_at

    days_old = (Time.current - scraped_at) / 1.day

    case days_old
    when 0..1
      100
    when 1..3
      80
    when 3..7
      60
    when 7..14
      40
    when 14..30
      20
    else
      0
    end
  end
end
