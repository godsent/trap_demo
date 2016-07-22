class Trap::Block < Trap::Base
  aasm do 
    state :idle, after_enter: :unblock
    state :running, after_enter: :block
    state :paused, after_enter: :unblock
  end

  def init_variables
    assert(:event) { @event_id = @options[:event] }
    assert(:map) { @map_id = @options[:map] }
  end

  def block
    disable_all_switches @event_id
  end

  def unblock
    enable_switch @event_id, 'A'
  end

  def dense?
    true
  end

  def xes
    [event.x]
  end

  def yes
    [event.y]
  end

  def event
    $game_map.events[@event_id]
  end
end