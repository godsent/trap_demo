# messager - popup messages for RPG Maker VX ACE
### Зависимости
- AASM https://github.com/godsent/aasm
- Ticker https://github.com/godsent/ticker

### Как использовать:
- Установите AASM https://github.com/godsent/aasm
- Установите Ticker https://github.com/godsent/ticker
- Подключите этот скрипт как гем при помощи Side scripts loader (https://github.com/godsent/rpg-maker-side-script-loader)
или вставив batch.rb в скрипты проекта
- Просмотрите и отредактируйте при необходимости Messager::Vocab and Messager::Settings

### Особенности
- Пока не откючено в Messager::Settings.general этот скрипт будет автоматически отображать изменения золота и вещей.
- Так же пока не отключено скрипт отображает полученный урон, лечение, состояния и т.п. в бою. Работает только для battler c 
определенными screen_x и screen_y (т.е. только для врагов по умолчанию)
- Вы можете вызвать попап вручную при помощи следующего кода:
```
battler = $game_troop.members[0]
battler.message_queue.damage_to_hp 250
battler.message_queue.heal_tp 100
```
```
$game_player.message_queue.gain_item $data_items[1]
$game_player.message_queue.gain_armor $data_armors[2]
$game_player.message_queue.gain_weapon $data_weapons[3]
$game_player.message_queue.gain_gold 300
```
```
message = Message::Queue::Message.new :add_state
state = $data_states[3]
message.text = state.name
message.icon_index = state.icon_index
$game_troop.members.sample.message_queue.push message
```
