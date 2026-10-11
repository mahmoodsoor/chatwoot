module Soor
  class SalesTaskConversation
    class IdentityConflict < StandardError; end

    def initialize(task:, agent:)
      @task = task
      @agent = agent
    end

    def ensure_conversation!
      verify_linked_identity!
      inbox = whatsapp_inbox!
      ensure_agent_access!(inbox)
      source_id = whatsapp_source_id!
      contact_inbox = inbox.contact_inboxes.includes(:contact).find_by(source_id: source_id)
      contact = contact_inbox&.contact || find_or_create_contact!
      check_contact_identity!(contact)
      contact_inbox ||= inbox.contact_inboxes.create_or_find_by!(source_id: source_id) do |record|
        record.contact = contact
      end
      raise IdentityConflict, 'WhatsApp number belongs to another contact' unless contact_inbox.contact_id == contact.id

      conversation = @task.conversation if @task.conversation&.contact_inbox_id == contact_inbox.id &&
                                           @task.conversation&.contact_id == contact.id &&
                                           @task.conversation&.inbox_id == inbox.id
      conversation ||= contact_inbox.conversations.where(account_id: @task.account_id).order(id: :desc).first
      conversation ||= create_whatsapp_conversation!(contact, contact_inbox, inbox)
      @task.update!(contact: contact, conversation: conversation)
      conversation
    end

    private

    def whatsapp_inbox!
      inboxes = @task.account.inboxes.where(channel_type: 'Channel::Whatsapp').limit(2).to_a
      raise IdentityConflict, 'No WhatsApp inbox is configured' if inboxes.empty?
      raise IdentityConflict, 'More than one WhatsApp inbox; choose the correct inbox before adding a note' if inboxes.many?

      inboxes.first
    end

    def whatsapp_source_id!
      raise IdentityConflict, 'A customer phone number is required for a WhatsApp note' if @task.phone_number.blank?

      @task.phone_number.delete_prefix('+')
    end

    def ensure_agent_access!(inbox)
      return if administrator? || @agent.inboxes.where(account_id: @task.account_id).exists?(id: inbox.id)

      raise IdentityConflict, 'You need access to the WhatsApp inbox to add this note'
    end

    def administrator?
      @agent.account_users.find_by(account_id: @task.account_id)&.administrator?
    end

    def verify_linked_identity!
      contact = @task.contact
      return unless contact

      check_contact_identity!(contact)
    end

    def check_contact_identity!(contact)
      raise IdentityConflict, 'Linked contact belongs to another account' unless contact.account_id == @task.account_id
      if @task.phone_number.present? && contact.phone_number.present? && @task.phone_number != contact.phone_number
        raise IdentityConflict, 'Zoho phone changed; verify the Chatwoot contact before adding a note'
      end
      return if @task.email.blank? || contact.email.blank? || @task.email.casecmp?(contact.email)

      raise IdentityConflict, 'Zoho email changed; verify the Chatwoot contact before adding a note'
    end

    def find_or_create_contact!
      return @task.contact if @task.contact&.account_id == @task.account_id

      contacts = @task.account.contacts
      identifier = "soor-zoho-contact:#{@task.zoho_contact_id}"
      by_id = contacts.find_by(identifier: identifier)
      by_phone = contacts.find_by(phone_number: @task.phone_number) if @task.phone_number.present?
      by_email = contacts.where('lower(email) = ?', @task.email.downcase).first if @task.email.present?
      matches = [by_id, by_phone, by_email].compact.uniq
      raise IdentityConflict, 'Phone and email match different Chatwoot contacts' if matches.size > 1

      if matches.first
        check_contact_identity!(matches.first)
        return matches.first
      end

      contacts.create!(
        identifier: identifier,
        name: @task.customer_name,
        phone_number: @task.phone_number,
        email: @task.email
      )
    end

    def create_whatsapp_conversation!(contact, contact_inbox, inbox)
      Conversation.create!(
        account: @task.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
        status: :resolved, custom_attributes: { soor_sales_task: true }
      )
    end
  end
end
