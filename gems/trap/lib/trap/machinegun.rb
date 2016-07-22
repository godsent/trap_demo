class Trap::Machinegun < Trap::Base
  include Trap::Defaults::Machinegun

  aasm do
    event :pause do
      transitions from: :running, to: :paused do
        after do
          untrack
          firebolls.each(&:pause)
        end
      end

      transitions from: :idle, to: :idle do
        after { firebolls.each(&:pause) }
      end
    end

    event :resume do
      transitions from: :paused, to: :running do
        after do
          track
          firebolls.each(&:resume)
        end
      end

      transitions from: :idle, to: :idle do
        after { firebolls.each(&:resume) }
      end
    end
  end

  def init_variables
    assert(:map) { @map_id = @options[:map] }
    assert(:route) { @route  = @options[:route] }
    @interval =  @options[:interval]
    @launched = 0
    @salt = Time.now.to_i + rand(999999)
    @last_fired_at = 0
  end

  def max_missiles
    @options[:max_missiles] || Float::INFINITY
  end

  def max_missiles=(number)
    @options[:max_missiles] ||= 0
    @options[:max_missiles] = number
  end

  def firebolls
    Trap[/#{@salt}/]
  end

  private

  def tick_job
    super
    if ints = @options[:intervals]
      index = @launched % ints.length
      if @ticked > 0 && @last_fired_at + ints[index] * slow <= @ticked
        fire
        @last_fired_at = @ticked
      end
    else
      fire if @ticked % speed == 0
    end
  end

  def default_speed
    @interval
  end

  def fire
    if fire?
      @launched += 1
      missile_klass.build(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow! @slow, @slowed_for, @slowed_at if slowed?
      end.run
      on_launch!
    end
  end

  def missile_klass
    Trap::Fireboll
  end

  def fire?
    running? && @launched < max_launches && firebolls.count < max_missiles
  end

  def max_launches
    @options[:max_launches] || Float::INFINITY
  end

  def new_options
    map, route = @map_id, @route.copy
    dmg, spd = @options[:damage], @options[:speed]
    sprite_options = @options[:sprite]
    state_ids = @options[:states]
    solid_flag = @options[:solid]
    bgs_value = @options[:bgs]
    bgs_value_set = @options.has_key?(:bgs)
    proc do
      map map
      route route
      damage dmg if dmg
      speed spd if spd
      sprite sprite_options if sprite_options
      states  state_ids if state_ids
      solid true if solid_flag
      bgs bgs_value if bgs_value_set
    end
  end

  def fireboll_name
    "#{@salt}#{@launched}"
  end

  def on_launch!
    if code = @options[:on_launch]
      eval code
    end
  end
end
