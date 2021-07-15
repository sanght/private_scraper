class CreateSellers < ActiveRecord::Migration[6.0]
  def change
    create_table :sellers do |t|
      t.string :merchant_id
      t.string :address
      t.string :city
      t.string :state
      t.string :country
      t.float :star_rating
      t.integer :total_rating

      t.timestamps
    end
  end
end
