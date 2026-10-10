module Soor
  class SalesTaskConversation
    class IdentityConflict < StandardError; end

    def initialize(task:, agent:)
      @task = task
      @agent = agent
    end

    def ensure_conversation!
      ensure_sales_inbox_member!
      verify_linked_identity!
      if @task.conversation&.contact_id == @task.contact_id && @task.contact_id.present?
        return @task.conversation if agent_can_see?(@task.conversation)
      end

      contact = find_or_create_contact!
      conversations = contact.conversations.where(account_id: @task.account_id)
      unless administrator?
        conversations = conversations.where(inbox_id: @agent.inboxes.where(account_id: @task.account_id).select(:id))
      end
      conversation = conversations.order(id: :desc).first
      conversation ||= create_private_conversation!(contact)
      @task.update!(contact: contact, conversation: conversation)
      conversation
    end

    private

    def ensure_sales_inbox_member!
      inbox = @task.account.inboxes.find_by(name: 'SOOR Sales Notes', channel_type: 'Channel::Api')
      inbox&.inbox_members&.find_or_create_by!(user_id: @agent.id)
    end

    def administrator?
      @agent.account_users.find_by(account_id: @task.account_id)&.administrator?
    end

    def agent_can_see?(conversation)
      administrator? || @agent.inboxes.where(account_id: @task.account_id).exists?(id: conversation.inbox_id)
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

    def create_private_conversation!(contact)
      inbox = sales_inbox!
      contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
      contact_inbox ||= ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
      Conversation.create!(
        account: @task.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
        status: :resolved, custom_attributes: { soor_sales_task: true }
      )
    end

    def sales_inbox!
      account = @task.account
      account.with_lock do
        inbox = account.inboxes.find_by(name: 'SOOR Sales Notes', channel_type: 'Channel::Api')
        return inbox if inbox

        channel = Channel::Api.create!(account: account)
        inbox = account.inboxes.create!(name: 'SOOR Sales Notes', channel: channel, enable_auto_assignment: false)
        inbox.add_members(account.account_users.pluck(:user_id))
        inbox
      end
    end
  end
end
