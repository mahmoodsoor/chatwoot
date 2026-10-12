class AddLeadSourceToSoorSalesTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :soor_sales_tasks, :lead_source, :string
    add_index :soor_sales_tasks, [:account_id, :lead_source]
  end
end
