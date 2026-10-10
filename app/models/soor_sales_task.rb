class SoorSalesTask < ApplicationRecord
  TASK_TYPES = %w[welcome_call follow_up documents quote renewal other].freeze
  STAGES = %w[new attempted contacted follow_up quote_sent won lost].freeze

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  validates :zoho_contact_id, presence: true, format: { with: /\A\d{1,30}\z/ }, uniqueness: { scope: :account_id }
  validates :customer_name, presence: true, length: { maximum: 180 }
  validates :phone_number, length: { maximum: 32 }
  validates :phone_number, allow_blank: true, format: { with: /\A\+[1-9]\d{1,14}\z/ }
  validates :email, length: { maximum: 254 }
  validates :email, allow_blank: true, format: { with: Devise.email_regexp }
  validates :task_type, inclusion: { in: TASK_TYPES }
  validates :stage, inclusion: { in: STAGES }
  validates :vehicle, jsonb_attributes_length: true
end
