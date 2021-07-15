class CreateProducts < ActiveRecord::Migration[6.0]
  def change
    create_table :products do |t|
      t.string :asin
      t.text :title
      t.text :description
      t.integer :rating
      t.float :star_rating

      t.timestamps
    end
  end
end
