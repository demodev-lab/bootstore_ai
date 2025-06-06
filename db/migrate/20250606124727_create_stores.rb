class CreateStores < ActiveRecord::Migration[8.0]
  def change
    create_table :stores do |t|
      t.string :name
      t.string :url
      t.integer :product_count
      t.decimal :average_price
      t.string :business_type
      t.string :status
      t.datetime :scraped_at

      t.timestamps
    end
  end
end
