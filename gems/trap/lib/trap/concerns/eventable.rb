module Trap::Concerns::Eventable
  def on(event, object, method, *args)
    @listeners[event] ||= []
    @listeners[event] << [object, method, args].flatten
  end

  def emit(event)
    (@listeners[event] || []).each { |a| a[0].send a[1], *a[2 .. -1] }
  end

  private

  def init_variables
    super
    @listeners = {}
    add_listeners_from_options
  end

  def add_listeners_from_options
    option_keys.each do |key|
      (@options[key] || {}).each do |event_id, c|
        on key, self, :disable_all_switches, event_id 
        on key, self, :enable_switch, event_id, c unless c == 'OFF'
      end
    end
  end
end