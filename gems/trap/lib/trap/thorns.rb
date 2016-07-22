module Trap
  class Thorns < ThornsBase
    include Trap::Defaults::Thorns
    attr_reader :ticked_was

    def init_variables
      super
      @hazard, @current = false, -1
    end

    private

    def tick_job
      super do 
        @hazard = false if @ticked % @options[:hazard_timeout] == 0
        next_thorns if frame == 0
        if @options[:timing].has_key? frame
          current_thorns
          name = @options[:se][@options[:timing][frame]]
          play_se name, sound_volume if name
        end
      end
    end

    def next_thorns
      change_current
      @hazard = true
    end

    def current_thorns
      disable_previouse_switch @events[@current]
      enable_current_switch @events[@current]
    end

    def change_current
      @current = @current >= max_current ? 0 : @current + 1
    end

    def deal_damage
      if same_map? && @hazard
        characters.select { |char| char.x == x && char.y == y }.each do |char|
          @hazard = false
          apply_damage char
          apply_states char
        end
      end
    end

    def event
      $game_map.events[@events[@current]]
    end

    def x
      event.x
    end

    def y
      event.y
    end

    def max_current
      @events.length - 1
    end
  end
end
