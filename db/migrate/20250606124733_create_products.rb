class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name
      t.decimal :price
      t.string :category
      t.string :image_url
      t.string :product_url
      t.string :status

      t.timestamps
    end
  end
end
