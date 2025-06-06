class AddRawDataToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :raw_data, :text
  end
end
