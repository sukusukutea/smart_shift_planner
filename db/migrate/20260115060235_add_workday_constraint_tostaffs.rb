class AddWorkdayConstraintTostaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :workday_constraint, :integer,
               null: false,
               default: 0
  end
end
