module Trap
  class Thorns < Base
    include Trap::Defaults::Thorns

    aasm do
      state :idle, initial: true
      state :running
      state :paused

      event :run do
        transitions from: :idle, to: :running do
          after { track }
        end
      end

      event :stop do
        transitions from: [:running, :paused], to: :idle do
          after { untrack }
        end
      end

      event :pause do
        transitions from: :running, to: :paused do
          after { untrack }
        end

        transitions from: :idle, to: :idle
      end

      event :resume do
        transitions from: :paused, to: :running do
          after { track }
        end

        transitions from: :idle, to: :idle
      end
    end

  	def init_variables
      @damage_value  = @options[:damage]
      @default_speed = @options[:speed]
      assert('map') { @map_id = @options[:map] }
      assert('events') { @events = @options[:events] }
      @ticked, @hazard, @current = 0, false, -1
  	end

    def tick
      @hazard = false if @ticked % @options[:hazard_timeout] == 0
      next_thorns if frame == 0
      current_thorns if @options[:timing].has_key? frame
      deal_damage
      @ticked += 1
    end

  	private

    def frame
      @ticked % speed
    end

    def next_thorns
      change_current
      @hazard = true
    end

    def current_thorns
      disable_previouse_switch
      enable_current_switch
    end

    def enable_current_switch
      unless @options[:timing][frame] == 'OFF'
        enable_switch @options[:timing][frame] 
      end
    end

    def disable_previouse_switch
      if prev_key = @options[:timing].keys.select { |k| k < frame }.max
        disable_switch @options[:timing][prev_key]
      end
    end

    def disable_switch(sw)
      turn_switch sw, false
    end

    def enable_switch(sw)
      play_se @options[:se][sw]
      turn_switch sw, true
    end

    def turn_switch(sw, bool)
      $game_self_switches[switch_index(sw)] = bool
    end

    def change_current
      @current = @current >= max_current ? 0 : @current + 1
    end

    def deal_damage
      if same_map? && @hazard
        characters.select { |char| char.x == x && char.y == y }.each do |char|
          @hazard = false
          char.hp -= damage_value
          display_damage char
        end
      end
    end

  	def switch_index(char = 'A')
  	  [@map_id, @events[@current], char]
  	end

    def event
      $game_map.events[@events[@current]] if same_map?
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