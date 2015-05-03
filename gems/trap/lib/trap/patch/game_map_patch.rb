class Game_Map
  attr_reader :map_id

  def id
    map_id
  end

  alias original_setup_for_trap setup 
  def setup(map_id)
    Trap.for_map(@map_id).each(&:pause)
    original_setup_for_trap map_id 
    Trap.for_map(@map_id).each(&:resume)
  end
end