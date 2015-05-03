 class Game_Interpreter
  #--------------------------------------------------------------------------
  # * Change Gold
  #--------------------------------------------------------------------------
  alias command_125_for_messager command_125
  def command_125
    value = operate_value(@params[0], @params[1], @params[2])
    if Messager::Settings.general[:monitor_gold]
      $game_player.message_queue.gain_gold value
    end
    command_125_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Items
  #--------------------------------------------------------------------------
  alias command_126_for_messager command_126
  def command_126
    value = operate_value(@params[1], @params[2], @params[3])
    item  = $data_items[@params[0]]
    if Messager::Settings.general[:monitor_items] && item
      $game_player.message_queue.gain_item item, value
    end
    command_126_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Weapons
  #--------------------------------------------------------------------------
  alias command_127_for_messager command_127
  def command_127
    value  = operate_value(@params[1], @params[2], @params[3])
    weapon = $data_weapons[@params[0]]
    if Messager::Settings.general[:monitor_weapons] && weapon
      $game_player.message_queue.gain_weapon weapon, value
    end
    command_127_for_messager 
  end
  #--------------------------------------------------------------------------
  # * Change Armor
  #--------------------------------------------------------------------------
  alias command_128_for_messager command_128
  def command_128
    value = operate_value(@params[1], @params[2], @params[3])
    armor = $data_armors[@params[0]]
    if Messager::Settings.general[:monitor_armors] && armor
      $game_player.message_queue.gain_armor armor, value
    end
    command_128_for_messager
  end
end