# Trap - traps for RPG Maker VX ACE
Ловушки для RPG Maker VX ACE. Демо - https://github.com/godsent/trap_demo

###Как установить
- Подключите AASM https://github.com/godsent/aasm
- Подключите Ticker https://github.com/godsent/ticker
- Подключите Messager (Не обязательно) https://github.com/godsent/messager
- Подключите Trap как гем при помощи Side scripts loader https://github.com/godsent/rpg-maker-side-script-loader ИЛИ вставив batch.rb в скрипты проекта

###Как использовать
Для начала просмотрите Trap::Defaults и сделайте настройки по умолчанию для себя. Это позволит задавать меньше настроек при инициализации ловушки.
Всего добавляются три типа ловушек - Fireboll, Machinegun и Thorns

####Fireboll
Представляет собой снаряд, летящий по заданному маршруту. В конце маршрута, или при столкновении с игроком fireboll взрывается с настраивоемой анимацией и наносит урон.
Для того, чтобы создать fireboll:
```
fireboll = Trap::Fireboll.build 'fireboll1' do #предоставте методу .build уникальный селектор
  map 1    #ID карты, обязательный параметр
  speed 10 #скорость снаряда, чем меньше число, тем больше скорость
  damage 200 #урон от взрыва
  route do
    start 1, 1 #x, y
    down  1, 10
    right 10, 10
    up    10, 1
  end
  sprite do
    sprite_path 'Graphics/system/fireboll' #путь к срайту снаряда
    animation 11 #ID анимации взрыва
  end
end
fireboll.run
```
Теперь вы можете из любого момента игры получить доступ к объекту ловушки при помощи селектора
```
Trap['fireboll1'].stop
Trap['fireboll1'].run
```
Спрайт снаряда необходим. Он представляет собой рисунок 4 на 4 кадра, по четыре кадра для каждого направления
```
#down | up | right | left 
#down | up | right | left
#down | up | right | left
#down | up | right | left
```
Кадры каждого направления буду меняться с заданой частатой, так что снаряд может быть анимированным.

####Machinegun 
Machinegun запускает Fireboll автоматически с заданным интервалом, у него есть одна своя настройка - interval, все остальные настройки он передает Fireboll
```
trap = Trap::Machinegun.build 'machinegun1' do #предоставте методу .build уникальный селектор
  interval 200 #Интервал в кадрах
  map 1    #ID карты, обязательный параметр
  speed 10 #скорость снаряда, чем меньше число, тем больше скорость
  damage 200 #урон от взрыва
  route do
    start 1, 1 #x, y
    down  1, 10
    right 10, 10
    up    10, 1
  end
  sprite do
    sprite_path 'Graphics/system/fireboll' #путь к срайту снаряда
    animation 11 #ID анимации взрыва
  end
end
trap.run
```

####Thorns
В отличие от предыдущих Thorns работает с эвентами. Эта ловушка представляет собой набор эвентов, в котором для каждого эвента по очереди переключатся локальные переключатели от A до D. Если во время переключения на А на эвенте будет находится игрок - он получит урон.
Соответсвенно вы можете назначить на такие эвенты любую анимацию по своему вкусу.
```
#trap = Trap::Thorns.build 'thorns1' do #селектор
#  map 1             #map id - необходим
#  events 1, 2, 3, 4 #id эвентов, можно назначить через массив или range ([1, 2, 3, 4] или 1..4)
#  damage 20         #урон от шипов
#end
#trap.run
#Trap['thorns1'].stop
#Trap['thorns1'].run
```

### Особенности
- Ловушки корректно сохраняются и загружаются
- Пре переходе между картами ловушки предыдущий карты ставятся на паузу, а ловушке следующей карты - снимаются с паузы.
