module Trap
  class DJ
    DELAY = 5

    class << self
      def play(*args)
        dj.play(*args)
      end

      def stop(*args)
        dj.stop(*args)
      end

      def to_save
        dj
      end

      def reset(old_dj)
        @dj = old_dj 
      end

      def track!
        dj.force_track!
      end

      private

      def dj 
        @dj ||= new
      end
    end

    def initialize
      @channels = { 
        se: Channel::SE.new, bgs: Channel::BGS.new,
        bgm: Channel::BGM.new, me: Channel::ME.new
      }
      @delays = Hash.new(0)
    end

    def tick 
      eval_channels
      decrease_delays
    end

    def play(channel, name, volume) 
      track!
      @channels[channel].play name, volume
      name
    end

    def stop(channel)
      track!
      @channels[channel].stop
    end

    def eval_channels
      @channels.each do |name, channel|
        if @delays[name] <= 0 
          @delays[name] = DELAY 
          channel.act!
        end
      end
    end

    def force_track!
      @tracked = nil 
      track! 
    end

    private

    def decrease_delays
      @delays.each_key do |channel| 
        @delays[channel] -= 1 if @delays[channel] > 0
      end
    end

    def track!
      unless @tracked
        Ticker.track self
        @tracked = true
      end
    end
  end
end

require 'trap/dj/channel'