class CreateProductData < ActiveRecord::Migration[6.0]
  def change
    create_table :product_data do |t|
      t.string :product_id
      t.string :seller_id
      t.decimal :price
      t.string :ships_from
      t.integer :quantity

      t.timestamps
    end
  end
end
