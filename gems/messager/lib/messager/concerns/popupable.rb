module Messager::Concerns::Popupable
  def create_message_popup(battler, message)
    message_popups << Messager::Popup.new(battler, message)
  end

  def remove_message_popup(popup)
    self.message_popups -= [popup]
    popup.dispose unless popup.disposed?
  end

  def message_popups
    @message_popups ||= []
  end

  private

  def flush_message_popups
    message_popups.each(&:dispose)
    @message_popups = []
  end

  def update_message_popups
    message_popups.each(&:update)
  end

  def self.included(klass)
    klass.class_eval do 
      attr_reader :viewport2
      attr_writer :message_popups 

      alias original_initialize_for_message_popups initialize
      def initialize
      	flush_message_popups
      	original_initialize_for_message_popups
      end

      alias original_dispose_for_message_popups dispose
      def dispose
        flush_message_popups
        original_dispose_for_message_popups
      end

      alias original_update_for_message_popups update
      def update
        update_message_popups
        original_update_for_message_popups
      end
    end
  end
end