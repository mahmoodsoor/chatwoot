class CreateSoorWhatsappCallRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :soor_whatsapp_call_records do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :agent, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :call_id, null: false
      t.string :direction, null: false
      t.string :status, null: false
      t.string :phone_number
      t.datetime :started_at, null: false
      t.datetime :ring_expires_at
      t.datetime :answered_at
      t.datetime :ended_at
      t.string :end_reason
      t.string :source
      t.text :outcome
      t.timestamps
    end

    add_index :soor_whatsapp_call_records, [:account_id, :call_id], unique: true, name: 'index_soor_calls_on_account_and_call_id'
    add_index :soor_whatsapp_call_records, [:account_id, :started_at], name: 'index_soor_calls_on_account_and_started_at'
  end
end
