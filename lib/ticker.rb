#Ticker
#Allows:
#a) Call block of code in timeout in frames
#b) Track object so #tick method in the object will be called on every frame
#author: Iren_Rin
#restrictions of use: none
#How to use
#a) In any object
# timeout_in_frames = 80
# Ticker.delay timeout_in_frames do
#   puts 'finally'
# end
#b) In any object with #tick method inside
# Ticker.track self #tick method will be called at every frame
#
#Track and Delay queues will be flush during switches between some scenes.
#There are three flush strategies
#a) :soft - queues flush during switching to any scene
#b) :middle - queues flush during switching to Scene_Title, Scene_End, Scene_Gameover and Scene_Battle
#c) :hard - queues flush during switching to Scene_Title and Scene_Gameover
#By default Ticker.delay uses :middle strategy and
#Ticker.track uses :hard strategy
#You can change it with following
#a)
# timeout_in_frames = 80
# Ticker.delay timeout_in_frames, :hard do
#   puts 'finally'
# end
#b)
# Ticker.track self, :soft
#
module Ticker
  VERSION = 0.2
  FLUSH_STRATEGIES = Hash.new [Scene_Base]
  FLUSH_STRATEGIES[:hard] = [Scene_Title, Scene_Gameover]
  FLUSH_STRATEGIES[:middle] = [Scene_Title, Scene_End, Scene_Gameover, Scene_Battle]

  def current_klass=(klass)
    queue[klass] ||= []
    tracked[klass] ||= []
    @current_klass = klass
  end

  def track(object, strategy = :hard)
    unless tracked[@current_klass].include? [object, strategy]
      tracked[@current_klass] << [object, strategy]
    end
  end

  def untrack(object)
    tracked.each { |klass, arr| arr.reject! { |arr| arr[0] == object } }
  end

  def delay(frames, strategy = :middle, &job)
    queue[@current_klass] << [frames, strategy, job]
  end

  def tick
    tick_queue
    tick_tracked
    self.ticked += 1
  end

  def flush
    b = proc do |arr|
      (FLUSH_STRATEGIES[arr[1]] & @current_klass.ancestors).any?
    end
    tracked.each { |klass, arr| arr.reject!(&b) }
    queue.each { |klass, arr| arr.reject!(&b) }
  end

  def queue
    @queue ||= {}
  end

  def tracked
    @tracked ||= {}
  end

  def clear_queue
    queue.each { |klass, arr| arr.reject! { |arr| arr[0] <= 0 } }
  end

  def ticked
    @ticked || 0
  end

  def ticked=(val)
    @ticked = val
  end

  private

  def tick_queue
    queue[@current_klass].each do |arr|
      arr[0] -= 1
      arr[2].call if arr[0] <= 0
    end
    clear_queue
  end

  def tick_tracked
    tracked[@current_klass].dup.each do |arr|
      arr[0].tick
    end
  end

  extend self
end

class Scene_Base
  alias original_start_for_ticker start
  def start
    Ticker.current_klass = self.class
    Ticker.flush
    original_start_for_ticker
  end

  alias original_update_basic_for_ticker update_basic
  def update_basic
    original_update_basic_for_ticker
    Ticker.tick
  end

  alias original_terminate_for_ticker terminate
  def terminate
    original_terminate_for_ticker
    Ticker.flush
  end
end
