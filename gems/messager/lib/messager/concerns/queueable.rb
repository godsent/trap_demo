module Messager::Concerns::Queueable
  def message_queue
    @message_queue ||= Messager::Queue.new(self)
  end
end