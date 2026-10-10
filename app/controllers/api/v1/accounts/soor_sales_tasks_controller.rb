class Api::V1::Accounts::SoorSalesTasksController < Api::V1::Accounts::BaseController
  before_action :require_agent

  def index
    scope = Current.account.soor_sales_tasks.includes(:assignee, :conversation)
    scope = scope.where(stage: params[:stage]) if SoorSalesTask::STAGES.include?(params[:stage])
    scope = scope.where(assignee_id: Current.user.id) if params[:mine] == 'true'
    scope = scope.where(assignee_id: nil) if params[:unassigned] == 'true'
    scope = scope.where('due_at < ?', Time.current) if params[:overdue] == 'true'
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip.first(100))}%"
      scope = scope.where('customer_name ILIKE :q OR phone_number ILIKE :q OR email ILIKE :q', q: query)
    end
    page = params[:page].to_i.clamp(1, 10_000)
    tasks = scope.order(Arel.sql('CASE WHEN due_at IS NULL THEN 1 ELSE 0 END'), :due_at, :created_at)
                 .page(page).per(30)
    render json: {
      tasks: tasks.map { |task| serialize(task) },
      meta: { page: page, total: tasks.total_count, pages: tasks.total_pages },
      counts: Current.account.soor_sales_tasks.group(:stage).count
    }
  end

  def update
    task = Current.account.soor_sales_tasks.find(params[:id])
    updates = params.require(:task).permit(:task_type, :stage, :assignee_id, :due_at, :outcome)
    outcome = updates.delete(:outcome).to_s.strip
    return render_error('Outcome is too long') if outcome.length > 3000
    return render_error('Invalid task type') if updates[:task_type].present? && !SoorSalesTask::TASK_TYPES.include?(updates[:task_type])
    return render_error('Invalid stage') if updates[:stage].present? && !SoorSalesTask::STAGES.include?(updates[:stage])

    if updates.key?(:assignee_id)
      id = updates[:assignee_id].presence
      return render_error('Agent is not in this account') if id && !Current.account.account_users.exists?(user_id: id)

      updates[:assignee_id] = id
    end
    if updates.key?(:due_at) && updates[:due_at].present?
      due = Time.iso8601(updates[:due_at]) rescue nil
      return render_error('Invalid due date') unless due

      updates[:due_at] = due
    end
    if %w[attempted contacted follow_up quote_sent won lost].include?(updates[:stage]) && outcome.blank?
      return render_error('Record what happened before changing this stage')
    end

    task.with_lock do
      before = task.attributes.slice('task_type', 'stage', 'assignee_id', 'due_at')
      task.assign_attributes(updates.to_h)
      changed = before.any? { |key, value| task.public_send(key) != value }
      return render_error('Add an outcome or change the task') unless changed || outcome.present?

      conversation = Soor::SalesTaskConversation.new(task: task, agent: Current.user).ensure_conversation!
      task.last_updated_at = Time.current
      task.save!
      content = "Sales task update · #{task.task_type.humanize} · #{task.stage.humanize}"
      content += "\nDue: #{task.due_at.in_time_zone('Asia/Bahrain').strftime('%d %b %Y, %H:%M %Z')}" if task.due_at
      content += "\nOwner: #{task.assignee&.name || 'Unassigned'}"
      content += "\n#{outcome}" if outcome.present?
      Messages::MessageBuilder.new(Current.user, conversation, { content: content, private: true, message_type: 'outgoing' }).perform
    end
    render json: { task: serialize(task.reload), note_added: true }
  rescue Soor::SalesTaskConversation::IdentityConflict => error
    render_error(error.message, :conflict)
  rescue ActiveRecord::RecordInvalid => error
    render_error(error.record.errors.full_messages.join(', '))
  end

  def open_conversation
    task = Current.account.soor_sales_tasks.find(params[:id])
    conversation = task.with_lock do
      Soor::SalesTaskConversation.new(task: task, agent: Current.user).ensure_conversation!
    end
    render json: { conversation_id: conversation.display_id }
  rescue Soor::SalesTaskConversation::IdentityConflict => error
    render_error(error.message, :conflict)
  rescue ActiveRecord::RecordInvalid => error
    render_error(error.record.errors.full_messages.join(', '))
  end

  # Called by the existing Zoho/n8n integration with a Chatwoot administrator token.
  # Zoho is read-only; repeated imports refresh display data without resetting agent work.
  def sync
    return head :forbidden unless Current.account_user.administrator?

    records = params.require(:contacts)
    return render_error('Send 1–100 contacts') unless records.is_a?(Array) && records.length.between?(1, 100)

    ids = []
    SoorSalesTask.transaction do
      records.each do |raw|
        raise ArgumentError, 'Each contact must be an object' unless raw.is_a?(ActionController::Parameters)

        entry = raw.permit(:zoho_contact_id, :customer_name, :phone_number, :email, :registered_at,
                           vehicle: %i[make model year plate registration_expiry registration_status])
        id = entry[:zoho_contact_id].to_s
        raise ArgumentError, 'Invalid Zoho contact ID' unless id.match?(/\A\d{1,30}\z/)

        task = Current.account.soor_sales_tasks.find_or_initialize_by(zoho_contact_id: id)
        task.assign_attributes(entry.except(:zoho_contact_id).to_h)
        task.due_at ||= task.registered_at || Time.current if task.new_record?
        task.save!
        ids << task.id
      end
    end
    render json: { synced: ids.length, task_ids: ids }
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    render_error(error.message)
  end

  private

  def require_agent
    head :forbidden unless Current.user.is_a?(User)
  end

  def render_error(message, status = :unprocessable_entity)
    render json: { error: message }, status: status
  end

  def serialize(task)
    {
      id: task.id, zoho_contact_id: task.zoho_contact_id,
      customer_name: task.customer_name, phone_number: task.phone_number, email: task.email,
      vehicle: task.vehicle, task_type: task.task_type, stage: task.stage,
      registered_at: task.registered_at, due_at: task.due_at, last_updated_at: task.last_updated_at,
      assignee: task.assignee && { id: task.assignee.id, name: task.assignee.name },
      conversation_id: task.conversation&.display_id
    }
  end
end
