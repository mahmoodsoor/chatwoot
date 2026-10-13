class SoorSalesTask < ApplicationRecord
  TASK_TYPES = %w[welcome_call follow_up documents quote renewal other].freeze
  STAGES = %w[new attempted contacted follow_up quote_sent won lost].freeze
  LEAD_SOURCES = %w[instagram tiktok google referral existing_customer website other not_asked].freeze
  CALL_OUTCOMES = %w[expensive other_company not_due end_of_month other no_available_quotes].freeze

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
  validates :lead_source, inclusion: { in: LEAD_SOURCES }, allow_nil: true
  validates :call_outcome, inclusion: { in: CALL_OUTCOMES }, allow_nil: true
  validates :call_outcome_detail, length: { maximum: 180 }
  validates :vehicle, jsonb_attributes_length: true
  validate :call_outcome_detail_required

  private

  def call_outcome_detail_required
    return unless %w[other_company other].include?(call_outcome) && call_outcome_detail.blank?

    errors.add(:call_outcome_detail, 'must be specified for this call outcome')
  end
end
