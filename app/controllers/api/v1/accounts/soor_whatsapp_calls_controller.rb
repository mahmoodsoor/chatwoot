class Api::V1::Accounts::SoorWhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :require_agent
  before_action :calling_inbox
  before_action :load_call, only: %i[show accept reject terminate]

  def index
    render json: { calls: calling.list.map { |call| serialize(call) } }
  end

  def show
    render json: serialize(@call)
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
    raise ActiveRecord::RecordNotFound unless id.match?(/\A[a-zA-Z0-9_.-]{1,200}\z/)

    @call = calling.find(id)
    raise ActiveRecord::RecordNotFound unless @call
  end

  def serialize(call)
    result = calling.public_call(call)
    result['sdp_answer'] = nil if call['direction'] == 'outbound' && call['agent_id'] != Current.user.id
    result
  end

  rescue_from Soor::WhatsappCalling::Error do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
