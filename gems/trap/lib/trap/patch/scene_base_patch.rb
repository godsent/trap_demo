class Scene_Base
  alias original_terminate_for_trap terminate
  def terminate
    original_terminate_for_trap
    if [Scene_Title, Scene_Gameover].include? self.class
      Trap.flush
    end
  end
end
