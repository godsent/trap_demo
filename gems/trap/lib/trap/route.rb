class Trap::Route
  def self.draw(&block)
    new.tap { |route| route.instance_eval(&block) }
  end

  def initialize(cells = [])
    @cells, @index = cells, 0
  end

  def start(x, y)
    @cells << [x, y]
  end

  %w(down up left right).each do |method_name|
    define_method method_name do |*args|
      exact_method_name = %w(up down).include?(method_name) ? 'exact_y' : 'exact_x'
      __send__(exact_method_name, args) { __send__ "step_#{method_name}" }
    end
  end

  def cell
    if @index < @cells.size
      current_index = @index
      @index += 1
      @cells[current_index]
    end
  end

  def to_enum!
    @cells = @cells.each
  end

  def copy
    self.class.new @cells
  end

  private

  def exact_y(args)
    if args.size > 1
      yield until y == args[1]
    else
      args[0].times { yield }
    end
  end

  def exact_x(args)
    if args.size > 1
      yield until x == args[0]
    else
      args[0].times { yield }
    end
  end

  def step_down
    @cells.last << :down
    @cells << [x, y + 1]
  end

  def step_up
    @cells.last << :up
    @cells << [x, y - 1]
  end

  def step_left
    @cells.last << :left
    @cells << [x - 1, y]
  end

  def step_right
    @cells.last << :right
    @cells << [x + 1, y]
  end

  def x
    @cells.last.first
  end

  def y
    @cells.last[1]
  end
end
