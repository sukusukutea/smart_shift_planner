class AddConfirmableToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      # confirmable
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at

      # reconfirmable=true 用（あなたは devise.rb で true）
      t.string   :unconfirmed_email
    end

    add_index :users, :confirmation_token, unique: true
    add_index :users, :unconfirmed_email
  end
end
