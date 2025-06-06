class CreateSearchFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :search_filters do |t|
      t.string :name
      t.string :filter_type
      t.string :value
      t.boolean :active
      t.string :user

      t.timestamps
    end
  end
end
