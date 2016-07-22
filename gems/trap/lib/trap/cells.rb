class Trap::Cells < Trap::Base 
  include Trap::Defaults::Cells

  aasm do 
    event :run do
      transitions from: :idle, to: :running do
        after do 
          track 
          enable_enabled_events
        end
      end
    end

    event :stop do
      transitions from: [:running, :paused], to: :idle do
        after do 
          untrack
          disable_all_events 
        end
      end

      transitions from: :idle, to: :idle
    end
  end

  def init_variables
    assert('map') { @map_id = @options[:map] }
    assert('events') { @events = @options[:events] }
    assert('enabled_events') { @enabled_events = @options[:enabled_events] }
    assert('columns') { @columns = @options[:columns] }
    assert('offset_x') { @offset_x = @options[:corner][0] }
    assert('offset_x') { @offset_y = @options[:corner][1] }
    @damage  = @options[:damage]
    @hazard_delay = @options[:hazard_delay]
    @dealed = Hash.new(-Float::INFINITY)
  end

  def teleport_if_closed 
    if @teleport_reserved_at 
      if @teleport_reserved_at + 120 < @ticked
        @teleport_reserved_at = nil 
        @teleported = nil
      elsif @teleport_reserved_at + 119 < @ticked
        refresh_trap
      elsif @teleport_reserved_at + 60 < @ticked && !@teleported
        $game_player.reserve_transfer @map_id, *@options[:teleport]
        @teleported = true
      end
    elsif @options[:teleport] && player_closed?
      @teleport_reserved_at = @ticked
    end
  end

  def refresh_trap
    disable_all_events 
    enable_enabled_events
  end

  def player_closed? 
    return false if @options[:entrances].to_a.any? do |(x, y)|
      $game_player.x == x && $game_player.y == y
    end

    x, y = $game_player.x - @offset_x, $game_player.y - @offset_y 
    return false if (x < 0 || y < 0) || (x >= columns || y >= rows) 

    [up(x, y), down(x, y), left(x, y), right(x, y)].compact.all? do |id|
      any_switch? id
    end
  end

  def set_current
    new_current = current_event 
    unless new_current == @current 
      @current = new_current
    end
  end

  def play_se_if_needed 
    if @se_needed 
      @se_needed = false 
      play_se @options[:se], sound_volume
    end
  end

  def bgs_needed? 
    super && hazard_events.any?
  end

  def distance_to_player
    hazard_events.map do |id| 
      ev = event(id)
      ((ev.x - $game_player.x) ** 2 + (ev.y - $game_player.y) ** 2) ** 0.5
    end.min || 100
  end

  private

  def tick_job
    super
    deal_damage 
    switch_neighbors
    set_current
    update_bgs
    play_se_if_needed
    teleport_if_closed
  end

  def enable_enabled_events
    @enabled_events.each do |id| 
      @se_needed = true 
      enable_switch id, 'A'
    end
  end

  def disable_all_events 
    @events.each { |id| disable_all_switches id }
  end

  def event(event_id)
    $game_map.events[event_id]
  end

  def deal_damage 
    characters.each do |char| 
      hazard_events.each do |id| 
        ev = event(id)
        if char.x == ev.x && char.y == ev.y && @dealed[id] < @ticked - @hazard_delay
          apply_damage char 
          apply_states char
          @dealed[id] = @ticked
        end
      end
    end
  end

  def switch_neighbors 
    current_ev = current_event
    if current_ev && current_ev != @current
      neighbors(current_ev).each do |id| 
        if any_switch? id
          disable_all_switches id
        else 
          @se_needed = true
          enable_switch id, 'A'
        end
      end
    end
  end 

  def hazard_events 
    @events.select { |id| any_switch? id }
  end

  def current_event 
    @events.find do |id| 
      event(id).x == $game_player.x && event(id).y == $game_player.y
    end
  end

  def columns
    @columns
  end

  def rows 
    (@events.size / @columns.to_f).ceil
  end

  def neighbors(id)
    x = event(id).x - @offset_x
    y = event(id).y - @offset_y
    [up(x, y), left(x, y), right(x, y), down(x, y)].compact
  end

  def up(x, y)
    @events[(y - 1) * columns + x] if y - 1 >= 0 
  end

  def down(x, y) 
    @events[(y + 1) * columns + x] if y + 1 < rows 
  end

  def left(x, y) 
    @events[y * columns + x - 1] if x - 1 >= 0
  end 


  def right(x, y)
    @events[y * columns + x + 1] if x + 1 < columns
  end
end