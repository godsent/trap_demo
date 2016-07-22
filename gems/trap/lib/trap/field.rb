module Trap
  class Field < ThornsBase
    include Trap::Defaults::Field

    def init_variables
      super
      @hazard = Hash.new false
      @safe_index = -1
      @random_safe_spots = {}
    end

    def new_vawe?
      frame == 0
    end

    def distance_to_player
      @events.map do |event_id|
        ev = event event_id
        ((ev.x - $game_player.x) ** 2 + (ev.y - $game_player.y) ** 2) ** 0.5
      end.min
    end

    private

    def tick_job
      super do 
        tick_hazard
        tick_safe_spots
        tick_timing
      end
    end

    def tick_timing
      if @options[:timing].has_key? frame
        play_se @options[:se][@options[:timing][frame]], sound_volume
        @events.each do |event|
          disable_switch event, 'D' if @options[:timing][frame] == 'A'

          unless current_safe_spots.include?(event)
            enable_current_switch event
            disable_previouse_switch event
          end

          if next_safe_spots.include?(event) && @options[:timing][frame] == 'OFF'
            enable_switch event, 'D' if highlight_safe_spots?
          end
        end
      end
    end

    def highlight_safe_spots?
      @options[:safe_spots][:highlight]
    end

    def tick_hazard
      if new_vawe?
        @hazard = Hash.new true
      elsif @ticked % @options[:hazard_timeout] == 0
        @hazard = Hash.new false 
      end
    end

    def tick_safe_spots
      switch_safe_spots if new_vawe?
    end

    def switch_safe_spots
      if n = @options[:safe_spots][:random]
        n = [n, @events.size].min
        @random_safe_spots[true]  = @random_safe_spots[false] || @events.sample(n)
        @random_safe_spots[false] = @events.sample(n)
      else
        @safe_index += 1
      end
    end

    def max_safe_spots_turns
      @options[:safe_spots][:safe_events].size
    end

    def current_safe_spots
      safe_spots true
    end

    def next_safe_spots
      safe_spots false
    end

    def safe_spots(current = true)
      if @options[:safe_spots][:random]
        random_safe_spots current
      else
        configured_safe_spots current
      end
    end

    def random_safe_spots(current)
      @random_safe_spots[current]
    end

    def configured_safe_spots(current)
      event_groups = @options[:safe_spots][:safe_events]
      if event_groups.any?
        index = (@safe_index + (current ? 0 : 1)) % max_safe_spots_turns
        event_groups[index]
      else
        []
      end
    end

    def event(event_id)
      $game_map.events[event_id]
    end

    def deal_damage
      return unless same_map?
      @events.each do |event_id|
        next if current_safe_spots.include?(event_id) || !@hazard[event_id]
        ev = event event_id
        targets = characters.select { |char| char.x == ev.x && char.y == ev.y }
        targets.each do |character|
          @hazard[event_id] = false
          apply_damage character
          apply_states character
        end
      end
    end
  end
end