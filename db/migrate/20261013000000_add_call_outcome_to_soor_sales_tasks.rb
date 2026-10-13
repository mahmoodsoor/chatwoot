class AddCallOutcomeToSoorSalesTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :soor_sales_tasks, :call_outcome, :string
    add_column :soor_sales_tasks, :call_outcome_detail, :string
    add_index :soor_sales_tasks, [:account_id, :call_outcome]
  end
end
