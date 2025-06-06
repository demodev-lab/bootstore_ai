class CreateEnhancedStoreFields < ActiveRecord::Migration[8.0]
  def change
    # Add new fields to stores table
    add_column :stores, :description, :text
    add_column :stores, :follower_count, :integer, default: 0
    add_column :stores, :rating, :decimal, precision: 3, scale: 2, default: 0.0
    add_column :stores, :error_message, :text

    # Add new fields to products table
    add_column :products, :review_count, :integer, default: 0
    add_column :products, :discount_rate, :integer, default: 0
    add_column :products, :scraped_at, :datetime

    # Add indexes for better performance
    add_index :stores, :business_type
    add_index :stores, :scraped_at
    add_index :products, :category
    add_index :products, :price
    add_index :products, :scraped_at
  end
end
