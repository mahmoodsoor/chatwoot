class SoorWhatsappCallRecord < ApplicationRecord
  SOURCES = %w[instagram tiktok google referral existing_customer website other not_asked].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation, optional: true
  belongs_to :agent, class_name: 'User', optional: true

  validates :call_id, presence: true, uniqueness: { scope: :account_id }
  validates :direction, inclusion: { in: %w[inbound outbound] }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :outcome, length: { maximum: 3000 }
end
