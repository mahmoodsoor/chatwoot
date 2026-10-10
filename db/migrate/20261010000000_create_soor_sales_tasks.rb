class CreateSoorSalesTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :soor_sales_tasks do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :assignee, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :zoho_contact_id, null: false
      t.string :customer_name, null: false
      t.string :phone_number
      t.string :email
      t.jsonb :vehicle, null: false, default: {}
      t.string :task_type, null: false, default: 'welcome_call'
      t.string :stage, null: false, default: 'new'
      t.datetime :registered_at
      t.datetime :due_at
      t.datetime :last_updated_at
      t.timestamps
    end

    add_index :soor_sales_tasks, [:account_id, :zoho_contact_id], unique: true
    add_index :soor_sales_tasks, [:account_id, :stage, :due_at]
    add_index :soor_sales_tasks, [:account_id, :assignee_id, :stage]
  end
end
