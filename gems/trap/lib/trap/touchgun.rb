class Trap::Touchgun < Trap::Machinegun
  include Trap::Defaults::Touchgun
  include Trap::Concerns::Eventable

  def self.bind(*traps)
    traps.flatten.each do |trap|
      (traps - [trap]).each do |trap2|
        trap.on :explode, trap2, :explode
      end
    end
  end

  def explode 
    if running?
      stop 
      firebolls.each(&:stop)
      emit :explode
    end
  end

  def fire
    if fire?
      @launched += 1
      touch = Trap::Touch.run(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow! @slow, @slowed_for, @slowed_at if slowed?
      end
      touch.on :catched, self, :catched 
      touch.on :evaded, self, :evaded
    end
  end

  private

  def init_variables
    @catched = 0 
    @evaded = 0
    super
  end

  def catched
    @catched += 1
    emit :catch_any

    case @options[:strategy]
    when :catch 
      if @catched >= max_launches
        emit :catch_all 
        stop
      end
    when :durable 
      #do nothing
    else
      explode
    end
  end

  def evaded
    @evaded += 1
    emit :evade_any

    case @options[:strategy]
    when :catch 
      explode
    when :durable 
      #do nothing
    else
      if @evaded >= max_launches
        emit :evade_all 
        stop
      end
    end
  end

  def option_keys
    [:catch_all, :catch_any, :evade_all, :evade_any]
  end
end