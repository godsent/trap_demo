class Trap::DJ::Channel::Base
  def initialize 
    flush_queue 
  end

  def play(name, volume)
    @queue << [name, volume]
  end

  def stop
    @stop_requested = true
  end

  def act!
    if @stop_requested && @queue.none?
      act_stop
    elsif @queue.any?
      act_play
    end
    flush_queue
  end

  private 

  def act_stop
    sound_klass.stop
  end

  def act_play
    play_new if volume > 0
  end

  def play_new
    sound_klass.new.tap do |sound|
      sound.volume = volume 
      sound.name = name 
      sound.from_trap_dj = true
      sound.play
    end
  end

  def name 
    message[0]
  end

  def volume 
    message[1]
  end

  def message
    @queue.max_by { |arr| arr[1] }
  end

  def flush_queue
    @queue = []
  end
end