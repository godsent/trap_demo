module Trap
  class ThornsBase < Base
    def init_variables
      @damage  = @options[:damage]
      @default_speed = @options[:speed]
      assert('map') { @map_id = @options[:map] }
      assert('events') { @events = @options[:events] }
    end

    def die 
      @dying = true 
    end

    private

    def tick_job
      super
      yield if block_given?
      deal_damage
      if @dying && @options[:timing][frame] == 'A'
        @dying = false 
        stop
      end
    end

    def enable_current_switch(event)
      unless @options[:timing][frame] == 'OFF'
        enable_switch event, @options[:timing][frame]
      end
    end

    def disable_previouse_switch(event)
      if prev_key = @options[:timing].keys.select { |k| k < frame }.max
        disable_switch event, @options[:timing][prev_key]
      end
    end

    def frame
      @ticked % speed
    end
  end
end