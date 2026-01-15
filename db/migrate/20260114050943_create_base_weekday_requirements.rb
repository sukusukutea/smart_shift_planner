class CreateBaseWeekdayRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :base_weekday_requirements do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :shift_kind, null: false, default: 0
      t.integer :day_of_week, null: false
      t.integer :role, null: false
      t.integer :required_number, null: false, default: 0

      t.timestamps
    end

    add_index :base_weekday_requirements,
              %i[user_id shift_kind day_of_week role],
              unique: true,
              name: "idx_base_weekday_requirements_unique"
  end
end
