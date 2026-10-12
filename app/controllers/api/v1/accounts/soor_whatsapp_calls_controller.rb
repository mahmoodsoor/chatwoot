class Api::V1::Accounts::SoorWhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :require_agent
  before_action :calling_inbox
  before_action :load_call, only: %i[show accept reject terminate]

  def index
    render json: { inbox_id: @inbox.id, calls: calling.list.map { |call| serialize(call) } }
  end

  def show
    render json: serialize(@call)
  end

  def performance
    authorize :report, :view?
    from = Date.iso8601(params[:from].presence || 29.days.ago.to_date.iso8601)
    to = Date.iso8601(params[:to].presence || Date.current.iso8601)
    return render_error('Select a valid date range of at most one year') if to < from || (to - from).to_i > 365

    zone = ActiveSupport::TimeZone[Current.account.reporting_timezone] || Time.zone
    starts_at = zone.local(from.year, from.month, from.day)
    ends_at = zone.local(to.year, to.month, to.day).end_of_day
    scope = SoorWhatsappCallRecord.where(account_id: Current.account.id, inbox_id: @inbox.id)
                                   .where(started_at: starts_at..ends_at)
    scope = scope.where(direction: params[:direction]) if %w[inbound outbound].include?(params[:direction])
    scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
    if params[:source].present?
      return render_error('Invalid source') unless SoorWhatsappCallRecord::SOURCES.include?(params[:source]) || params[:source] == 'unrecorded'

      scope = scope.where(source: params[:source] == 'unrecorded' ? nil : params[:source])
    end
    scope = filter_status(scope, params[:status]) if params[:status].present?
    return render_error('Invalid call status') unless scope

    total = scope.count
    answered = scope.where.not(answered_at: nil).count
    missed = scope.where(direction: 'inbound', answered_at: nil)
                  .where('ended_at IS NOT NULL OR ring_expires_at < ?', Time.current).count
    duration = scope.where.not(answered_at: nil).where.not(ended_at: nil)
                    .pick(Arel.sql('AVG(EXTRACT(EPOCH FROM ended_at - answered_at))'))
    pickup = scope.where(direction: 'inbound').where.not(answered_at: nil)
                  .pick(Arel.sql('AVG(EXTRACT(EPOCH FROM answered_at - started_at))'))
    agent_counts = scope.where.not(agent_id: nil).group(:agent_id).count
    agent_answered = scope.where.not(agent_id: nil).where.not(answered_at: nil).group(:agent_id).count
    names = Current.account.users.where(id: agent_counts.keys).pluck(:id, :name).to_h
    page = params[:page].to_i.clamp(1, 10_000)
    records = scope.includes(:agent, :conversation).order(started_at: :desc).page(page).per(25)
    render json: {
      metrics: { total: total, answered: answered, missed: missed,
                 answer_rate: total.zero? ? 0 : (answered * 100.0 / total).round(1),
                 average_duration_seconds: duration.to_f.round, average_pickup_seconds: pickup.to_f.round },
      sources: scope.group(:source).count,
      filter_agents: Current.account.users.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },
      agents: agent_counts.map { |id, count| { id: id, name: names[id], calls: count, answered: agent_answered[id] || 0 } },
      records: records.map { |record| serialize_record(record) },
      meta: { page: page, pages: records.total_pages, total: total }
    }
  rescue Date::Error
    render_error('Invalid date')
  end

  def outcome
    record = SoorWhatsappCallRecord.find_by!(account_id: Current.account.id, inbox_id: @inbox.id, call_id: params[:id])
    conversation = Current.account.conversations.find(record.conversation_id)
    authorize conversation, :show?
    text = params.require(:outcome).to_s.strip
    source = params.require(:source).to_s
    return render_error('Add a call outcome (up to 3000 characters)') if text.blank? || text.length > 3000
    return render_error('Select how the customer heard about SOOR') unless SoorWhatsappCallRecord::SOURCES.include?(source)

    record.with_lock do
      return render_error('An outcome has already been saved for this call') if record.outcome.present?

      content = "WhatsApp call outcome\nSource: #{source.humanize}\n#{text}"
      Messages::MessageBuilder.new(Current.user, conversation, { content: content, private: true, message_type: 'outgoing' }).perform
      record.update!(outcome: text, source: source)
    end
    render json: { saved: true }
  end

  def initiate
    conversation = Current.account.conversations.find(params.require(:conversation_id))
    authorize conversation, :show?
    raise Soor::WhatsappCalling::Error, 'This conversation is not in the calling inbox' unless conversation.inbox_id == @inbox.id

    render json: calling.initiate(conversation: conversation, agent: Current.user, sdp: params[:sdp_offer])
  end

  def accept
    render json: calling.accept(@call, agent: Current.user, sdp: params[:sdp_answer])
  end

  def reject
    raise Soor::WhatsappCalling::Error, 'This call is no longer ringing' unless @call['direction'] == 'inbound' && @call['status'] == 'ringing'

    render json: calling.finish(@call, action: 'reject')
  end

  def terminate
    raise Soor::WhatsappCalling::Error, 'Only the answering agent can end this call' unless @call['agent_id'] == Current.user.id

    render json: calling.finish(@call, action: 'terminate')
  end

  private

  def require_agent
    head :forbidden unless Current.user.is_a?(User)
  end

  def calling_inbox
    @inbox = Current.account.inboxes.includes(:channel).detect do |inbox|
      Soor::WhatsappCalling.enabled_for?(inbox.channel)
    end
    raise ActiveRecord::RecordNotFound, 'Calling inbox is not configured' unless @inbox

    authorize @inbox, :show?
  end

  def calling
    @calling ||= Soor::WhatsappCalling.new(@inbox.channel)
  end

  def load_call
    id = params[:id].to_s
    raise ActiveRecord::RecordNotFound unless id.match?(/\A[a-zA-Z0-9_.=+-]{1,200}\z/)

    @call = calling.find(id)
    raise ActiveRecord::RecordNotFound unless @call
  end

  def serialize(call)
    result = calling.public_call(call)
    result['sdp_answer'] = nil if call['direction'] == 'outbound' && call['agent_id'] != Current.user.id
    result
  end

  def filter_status(scope, status)
    case status
    when 'answered' then scope.where.not(answered_at: nil)
    when 'missed' then scope.where(direction: 'inbound', answered_at: nil).where('ended_at IS NOT NULL OR ring_expires_at < ?', Time.current)
    when 'unanswered' then scope.where(direction: 'outbound', answered_at: nil).where.not(ended_at: nil)
    when 'ongoing' then scope.where(ended_at: nil).where('answered_at IS NOT NULL OR ring_expires_at >= ?', Time.current)
    end
  end

  def serialize_record(record)
    { id: record.call_id, started_at: record.started_at, direction: record.direction,
      status: record_status(record), phone_number: record.phone_number,
      agent: record.agent&.name, conversation_display_id: record.conversation&.display_id,
      answered_at: record.answered_at, ended_at: record.ended_at,
      duration_seconds: record.answered_at && record.ended_at ? (record.ended_at - record.answered_at).to_i : nil,
      source: record.source, outcome: record.outcome }
  end

  def record_status(record)
    return 'answered' if record.answered_at && record.ended_at
    return 'ongoing' if record.answered_at
    return 'missed' if record.direction == 'inbound' && (record.ended_at || record.ring_expires_at && record.ring_expires_at < Time.current)
    return 'unanswered' if record.direction == 'outbound' && record.ended_at

    'ringing'
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  rescue_from Soor::WhatsappCalling::Error do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
