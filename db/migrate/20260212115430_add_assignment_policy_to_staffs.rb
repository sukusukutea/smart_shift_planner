class AddAssignmentPolicyToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :assignment_policy, :integer, null: false, default: 0
    add_index  :staffs, :assignment_policy
  end
end
