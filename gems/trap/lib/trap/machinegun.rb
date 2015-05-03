class Trap::Machinegun < Trap::Base
  include Trap::Defaults::Machinegun
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
    @firebolls_count, @ticked = 0, 0
    @salt = Time.now.to_i + rand(999)
  end

  def tick
    fire if @ticked % speed == 0
    @ticked += 1
  end

  private

  def default_speed
    @interval
  end

  def fire
    if running?
      @firebolls_count += 1
      Trap::Fireboll.build(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow = @slow if @slow
      end.run
    end
  end

  def new_options
    map, route = @map_id, @route.copy
    dmg, spd = @options[:damage], @options[:speed]
    sprite_options = @options[:sprite]
    proc do 
      map map
      route route
      damage dmg if dmg
      speed spd if spd
      sprite sprite_options if sprite_options
    end
  end

  def fireboll_name
    "#{@salt}#{@firebolls_count}"
  end

  def firebolls
    Trap[/#{@salt}/]
  end
end