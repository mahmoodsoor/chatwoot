module Soor
  class WhatsappCalling
    TTL = 1.day.to_i
    RING_TTL = 60
    API_VERSION = 'v25.0'.freeze

    class Error < StandardError; end

    def self.enabled_for?(channel)
      channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud' &&
        ENV['SOOR_WHATSAPP_CALL_PHONE_ID'].present? &&
        channel.provider_config['phone_number_id'].to_s == ENV['SOOR_WHATSAPP_CALL_PHONE_ID']
    end

    def initialize(channel)
      @channel = channel
      raise Error, 'WhatsApp calling is not configured for this inbox' unless self.class.enabled_for?(channel)
    end

    def list
      ids = Redis::Alfred.lrange(index_key, 0, 99)
      ids.filter_map { |id| find(id) }
    end

    def find(id)
      raw = Redis::Alfred.get(call_key(id))
      return if raw.blank?

      call = JSON.parse(raw)
      if call['direction'] == 'inbound' && call['status'] == 'ringing' && Time.iso8601(call['ring_expires_at']) < Time.current
        call['status'] = 'missed'
      end
      call
    end

    def initiate(conversation:, agent:, sdp:)
      validate_sdp!(sdp)
      recipient = conversation.contact_inbox&.source_id.presence || conversation.contact&.phone_number.to_s.delete('^0-9')
      raise Error, 'The contact has no WhatsApp number' if recipient.blank?

      recipient_param = recipient.match?(RegexHelper::WHATSAPP_BSUID_REGEX) ? :recipient : :to
      response = graph_post(action: 'connect', recipient_param => recipient, session: { sdp_type: 'offer', sdp: sdp })
      id = response.dig('calls', 0, 'id').to_s
      raise Error, 'Meta did not return a call ID' if id.blank?

      call = base_call(id, 'outbound').merge(
        'conversation_id' => conversation.id, 'conversation_display_id' => conversation.display_id,
        'contact_id' => conversation.contact_id,
        'agent_id' => agent.id, 'status' => 'ringing', 'recipient' => recipient
      )
      pending_answer = Redis::Alfred.get(pending_answer_key(id))
      call['sdp_answer'] = pending_answer if pending_answer.present?
      save(call)
      public_call(call)
    end

    def accept(call, agent:, sdp:)
      raise Error, 'This call is no longer ringing' unless call['status'] == 'ringing' && call['direction'] == 'inbound'
      validate_sdp!(sdp)
      # An atomic claim prevents two agents answering the same phone call.
      claimed = Redis::Alfred.set("#{call_key(call['id'])}:claim", agent.id, nx: true, ex: RING_TTL)
      raise Error, 'Another agent is answering this call' unless claimed

      begin
        graph_post(call_id: call['id'], action: 'pre_accept', session: { sdp_type: 'answer', sdp: sdp })
        graph_post(call_id: call['id'], action: 'accept', session: { sdp_type: 'answer', sdp: sdp })
        call.merge!('agent_id' => agent.id, 'status' => 'active', 'answered_at' => Time.current.iso8601)
        save(call)
        public_call(call)
      rescue StandardError
        Redis::Alfred.delete("#{call_key(call['id'])}:claim")
        raise
      end
    end

    def finish(call, action:)
      raise Error, 'This call has already ended' if call['status'] == 'ended'
      graph_post(call_id: call['id'], action: action)
      call.merge!('status' => 'ended', 'ended_at' => Time.current.iso8601)
      save(call)
      public_call(call)
    end

    def receive(payload)
      Array(payload[:entry]).each do |entry|
        Array(entry[:changes]).each do |change|
          next unless change[:field] == 'calls'
          value = change[:value] || {}
          next unless value.dig(:metadata, :phone_number_id).to_s == @channel.provider_config['phone_number_id'].to_s

          Array(value[:calls]).each { |event| receive_call_event(event) }
          Array(value[:statuses]).each { |status| receive_status(status) }
        end
      end
    end

    def public_call(call)
      call.except('sdp_offer', 'sdp_answer').merge(
        'sdp_offer' => (call['direction'] == 'inbound' && call['status'] == 'ringing' ? call['sdp_offer'] : nil),
        'sdp_answer' => (call['direction'] == 'outbound' ? call['sdp_answer'] : nil)
      )
    end

    private

    def receive_call_event(event)
      id = event[:id].to_s
      return if id.blank?

      call = find(id)
      case event[:event]
      when 'connect'
        if event.dig(:session, :sdp_type) == 'offer'
          return if call

          call = base_call(id, 'inbound').merge(
            'status' => 'ringing', 'caller' => event[:from].to_s,
            'sdp_offer' => event.dig(:session, :sdp),
            'ring_expires_at' => RING_TTL.seconds.from_now.iso8601
          )
          contact_inbox = @channel.inbox.contact_inboxes.find_by(source_id: event[:from].to_s)
          conversation = contact_inbox&.conversations&.order(id: :desc)&.first
          call['conversation_id'] = conversation.id if conversation
          call['conversation_display_id'] = conversation.display_id if conversation
          save(call)
        elsif call && call['direction'] == 'outbound'
          call['sdp_answer'] = event.dig(:session, :sdp)&.gsub('a=setup:actpass', 'a=setup:active')
          save(call)
        elsif event.dig(:session, :sdp_type) == 'answer'
          answer = event.dig(:session, :sdp)&.gsub('a=setup:actpass', 'a=setup:active')
          Redis::Alfred.set(pending_answer_key(id), answer, ex: RING_TTL) if answer.present?
        end
      when 'terminate'
        return unless call

        call.merge!('status' => 'ended', 'ended_at' => Time.current.iso8601, 'end_reason' => event[:terminate_reason])
        save(call)
      end
    end

    def receive_status(status)
      return unless status[:type] == 'call'

      call = find(status[:id].to_s)
      return unless call

      call['status'] = 'active' if status[:status] == 'ACCEPTED'
      save(call)
    end

    def graph_post(body)
      response = HTTParty.post(
        "https://graph.facebook.com/#{API_VERSION}/#{@channel.provider_config['phone_number_id']}/calls",
        headers: { 'Authorization' => "Bearer #{@channel.provider_config['api_key']}", 'Content-Type' => 'application/json' },
        body: { messaging_product: 'whatsapp' }.merge(body).to_json,
        timeout: 12
      )
      return response.parsed_response if response.success?

      code = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'code') : nil
      raise Error, 'The customer has not permitted this business to call them on WhatsApp' if code == 138006

      Rails.logger.warn("[SOOR WhatsApp Calling] Meta rejected call action: HTTP #{response.code}, code #{code}")
      raise Error, 'Meta rejected the WhatsApp call action'
    end

    def validate_sdp!(sdp)
      raise Error, 'Invalid WebRTC audio session' unless sdp.is_a?(String) && sdp.start_with?('v=0') && sdp.bytesize.between?(20, 32_000)
    end

    def base_call(id, direction)
      { 'id' => id, 'direction' => direction, 'inbox_id' => @channel.inbox.id,
        'account_id' => @channel.account_id, 'created_at' => Time.current.iso8601 }
    end

    def save(call)
      key = call_key(call['id'])
      Redis::Alfred.lpush(index_key, call['id']) unless Redis::Alfred.exists?(key)
      Redis::Alfred.setex(key, call.to_json, TTL)
      Redis::Alfred.expire(index_key, TTL)
    end

    def call_key(id)
      "soor:whatsapp_call:#{@channel.account_id}:#{@channel.inbox.id}:#{id}"
    end

    def index_key
      "soor:whatsapp_call:index:#{@channel.account_id}:#{@channel.inbox.id}"
    end

    def pending_answer_key(id)
      "#{call_key(id)}:pending_answer"
    end
  end
end
