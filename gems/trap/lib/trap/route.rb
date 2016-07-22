class Trap::Route
  def self.draw(&block)
    new.tap { |route| route.instance_eval(&block) }
  end

  def initialize(cells = [])
    @cells, @index = cells, 0
  end

  def start(x, y)
    @cells << { x: x, y: y }
  end

  %w(down up left right).each do |method_name|
    define_method method_name do |*args, &block|
      exact_method_name = %w(up down).include?(method_name) ? 'exact_y' : 'exact_x'
      send(exact_method_name, args) { send "step_#{method_name}" }
      @cells.last[:route] = self.class.draw(&block) if block
    end
  end

  def cycle!(direction = :down)
    @cycle = true
    @cells.last[:direction] = direction
  end

  def blink(x, y)
    @cells.last[:direction] = :blink
    @cells << { x: x, y: y }
  end

  def cycle?
    !!@cycle
  end

  def cell
    if @index < @cells.size || cycle?
      @cells[@index % @cells.size].tap { @index += 1 }
    end
  end

  def copy
    cells = copied_cells
    self.class.new(cells).tap do |route| 
      route.cycle! cells.last[:direction] if cycle?
    end
  end

  private

  def copied_cells
    @cells.map { |cell| copy_cell cell }
  end

  def copy_cell(cell)
    new_cell = cell.dup
    if route = cell[:route]
      new_cell[:route] = route.copy 
    end
    new_cell
  end

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
    @cells.last[:direction] = :down
    @cells << { x: x, y: y + 1 }
  end

  def step_up
    @cells.last[:direction] = :up
    @cells << { x: x, y: y - 1 }
  end

  def step_left
    @cells.last[:direction] = :left
    @cells << { x: x - 1, y: y }
  end

  def step_right
    @cells.last[:direction] = :right
    @cells << { x: x + 1, y: y }
  end
  
  def x
    @cells.last[:x]
  end

  def y
    @cells.last[:y]
  end
end