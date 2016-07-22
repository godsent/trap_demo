class Window_BattleLog
  METHODS = %w(
    display_action_results display_use_item display_hp_damage 
    display_mp_damage display_tp_damage
    display_counter display_reflection display_substitute
    display_failure display_miss display_evasion display_affected_status
    display_auto_affected_status display_added_states display_removed_states
    display_current_state display_changed_buffs display_buffs
  )
  
  METHODS.each { |name| alias_method "#{name}_for_messager", name }

  def queue(battler)
    @message_queues ||= {}
    @message_queues[battler] ||= battler.message_queue
  end

  def display_current_state(subject)
    unless enabled? subject
      display_current_state_for_messager subject
    end
  end

  def display_action_results(target, item)
    if enabled? target
      if target.result.used
        display_damage(target, item)
        display_affected_status(target, item)
        display_failure(target, item)
      end
    else
      display_action_results_for_messager target, item
    end
  end

  def display_use_item(subject, item)
    if enabled? subject
      queue(subject).push icon_message(
        item.icon_index,
        item.is_a?(RPG::Skill) ? :cast : :use, 
        item.name
      )
    else
      display_use_item_for_messager subject, item
    end
  end

  def display_hp_damage(target, item)
    if enabled? target
      return if target.result.hp_damage == 0 && item && !item.damage.to_hp?
      if target.result.hp_damage > 0 && target.result.hp_drain == 0
        target.perform_damage_effect
      end
      Sound.play_recovery if target.result.hp_damage < 0
      queue(target).push damage_message(target, :hp)
    else
      display_hp_damage_for_messager target, item
    end
  end

  def display_mp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.mp_damage == 0
      Sound.play_recovery if target.result.mp_damage < 0
      queue(target).push damage_message(target, :mp)
    else
      display_mp_damage_for_messager target, item
    end
  end

  def display_tp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.tp_damage == 0
      Sound.play_recovery if target.result.tp_damage < 0
      queue(target).push damage_message(target, :tp)
    else
      display_tp_damage_for_messager target, item
    end
  end

  def display_energy_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.energy_damage == 0
      Sound.play_recovery if target.result.energy_damage < 0
      queue(target).push damage_message(target, :energy)
    end
  end

  def display_counter(target, item)
    if enabled? target
      Sound.play_evasion
      queue(target).push text_message(
        Messager::Vocab::CounterAttack,
        :counter_attack
      )
    else
      display_counter_for_messager target, item
    end
  end

  def display_reflection(target, item)
    if enabled? target
      Sound.play_reflection
      queue(target).push text_message(
        Messager::Vocab::MagicReflection,
        :magic_reflection
      )
    else
      display_reflection_for_messager target, item
    end
  end

  def display_substitute(substitute, target)
    if enabled? target
      queue(target).push text_message(
        Messager::Vocab::Substitute,
        :substitute
      )
    else
      display_substitute_for_messager substitute, target
    end
  end

  def display_failure(target, item)
    if enabled? target
      if target.result.hit? && !target.result.success
        queue(target).push text_message(Messager::Vocab::NoEffect, :failure)
      end
    else
      display_failure_for_messager target, item
    end
  end

  def display_shield_block(target)
    queue(target).push text_message(Messager::Vocab::Block, :failure)
  end

  def display_miss(target, item)
    if enabled? target
      type, text = if !item || item.physical?
        Sound.play_miss
        [:miss, Messager::Vocab::Miss]
      else
        [:failure, Messager::Vocab::NoEffect]
      end
      queue(target).push text_message(text, type)
    else
      display_miss_for_messager target, item
    end
  end

  def display_evasion(target, item)
    if enabled? target
      if !item || item.physical?
        Sound.play_evasion
      else
        Sound.play_magic_evasion
      end
      queue(target).push text_message(Messager::Vocab::Evasion, :evasion)
    else
      display_evasion_for_messager target, item
    end
  end

  def display_affected_status(target, item)
    if enabled? target
      if target.result.status_affected?
        display_changed_states target
        display_changed_buffs target
      end
    else
      display_affected_status_for_messager target, item
    end
  end

  def display_auto_affected_status(target)
    if enabled? target
      display_affected_status target, nil
    else
      display_auto_affected_status_for_messager target
    end
  end

  def display_added_states(target)
    if enabled? target
      target.result.added_state_objects.each do |state|
        if state.id == target.death_state_id && Messager::Settings.general[:allow_collapse_effect]
          target.perform_collapse_effect
          wait
          wait_for_effect
        end 
        queue(target).push icon_message(state.icon_index, :icon, state.name)
      end
    else
      display_added_states_for_messager target
    end
  end

  def display_removed_states(target)
    unless enabled? target
      display_removed_states_for_messager target
    end
  end

  def display_changed_buffs(target)
    if enabled? target
      display_buffs(target, target.result.added_buffs, Vocab::BuffAdd)
      display_buffs(target, target.result.added_debuffs, Vocab::DebuffAdd)
    else
      display_changed_buffs_for_messager target
    end
  end

  def display_buffs(target, buffs, fmt)
    if enabled? target
      buffs.each do |param_id|
        lvl = target.instance_variable_get(:@buffs)[param_id]
        icon_index = target.buff_icon_index lvl, param_id
        queue(target).push icon_message(icon_index, :icon)
      end
    else
      display_buffs_for_messager target, buffs, fmt
    end
  end

  private

  def enabled?(target)
    return false unless Messager::Settings.general[:in_battle]
    [:screen_x, :screen_y].all? do |method_name|
      target.respond_to? method_name
    end
  end

  def text_message(text, type)
    message(type).tap { |m| m.text = text }
  end

  def icon_message(icon_index, type, text = '')
    message(type).tap do |object|
      object.icon_index = icon_index
      object.text = text
    end 
  end

  def damage_message(target, key)
    value = target.result.public_send("#{key}_damage").to_i
    message(value < 0 ? :"heal_#{key}" : :"damage_to_#{key}").tap do |the_message|
      the_message.damage = value
      the_message.critical = target.result.critical
    end
  end

  def message(type)
    Messager::Queue::Message.new type
  end
end