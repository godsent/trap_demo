class Scene_Base
  alias original_start_for_trap start
  def start
    original_start_for_trap
    flush_all_traps
  end

  private 

  def flush_all_traps 
    if [Scene_Title, Scene_Gameover, Scene_End].include? self.class
      Trap.flush
    end
  end
end
