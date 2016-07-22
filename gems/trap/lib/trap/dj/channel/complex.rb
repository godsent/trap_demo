module Trap::DJ::Channel
  class Complex < Base
    private

    def act_play
      if @current && @current.name == name 
        update_current
      elsif volume > 0
        @sound_was = sound_klass.last unless sound_klass.last.from_trap_dj?
        @current = play_new
      end
    end

    def act_stop
      super
      @current = nil 
      @sound_was.replay if @sound_was
    end

    def update_current
      if volume > 0 && @current.volume != volume
        @current.volume = volume 
        @current.replay 
      elsif volume <= 0 
        act_stop 
      end
    end
  end
end