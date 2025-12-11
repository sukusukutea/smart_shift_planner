class CreateStaffs < ActiveRecord::Migration[8.1]
  def change
    create_table :staffs do |t|
      t.references :occupation, null: false, foreign_key: true
      t.references :user,       null: false, foreign_key: true

      t.string :last_name,      null: false
      t.string :first_name,     null: false
      t.string :last_name_kana, null: false
      t.string :first_name_kana, null: false

      t.boolean :can_day,   null: false, default: false
      t.boolean :can_early, null: false, default: false
      t.boolean :can_late,  null: false, default: false
      t.boolean :can_night, null: false, default: false

      t.boolean :can_visit, null: false, default: false
      t.boolean :can_drive, null: false, default: false
      t.boolean :can_cook,  null: false, default: false

      t.timestamps
    end
  end
end
