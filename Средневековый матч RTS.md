# Средневековый матч RTS — журнал реверса

`PlaceId 13802699692` · `GameId 3918560032` · Creator **Spling** (group 15600763) · PlaceVersion 411
Игрок: **godlimaster11** (UserId 8618395275). Режим в этом сервере: `SINGLEPLAYER`, Reg EU, ReservedServer.
Это RTS-матч: у каждого игрока своё королевство (замок), строишь экономику/армию, цель — снести вражеский замок.

> Статусы: ✅ проверено вживую · ⚠️ гипотеза · ❌ отклонено сервером · 🔇 шум (read-only фон)

---

## 0. ГЛАВНОЕ (то, что жгло время) — читать первым

1. **Постройка отклоняется при неправильном Y.** `PlacementEvent` шлёт позицию превью, где
   `Y = groundY + hitboxHeight/2 + 0.02` (≈1.33 у виндмилла), а НЕ Y центра supply (≈0.28).
   Прошлая сессия слала Y supply ≈0.2/0.28 → сервер молча отклонял (без алерта, кэш не списывался).
   С правильным Y постройка проходит. ✅ ЭТО БЫЛ ГЛАВНЫЙ БАГ.
2. **AFK-латч реально забирает королевство боту** (юниты теряются, постройка/рекрут молча падают).
   ❌ VirtualInputManager (mouse-move/key) НЕ обновляет u49, если окно Roblox не в фокусе (а оно не в фокусе
   при работе через MCP) → латч срабатывает снова. **ПРАВИЛЬНО:** клиентский цикл шлёт `true` только если
   `workspace.Game.BotsEnabled.Value`==true. Ставлю `BotsEnabled.Value=false` НА КЛИЕНТЕ (луп раз в 0.4с) →
   цикл больше не латчит + спамлю `ChangeIdleState:FireServer(false)` для реклейма. ✅ держит контроль
   детерминированно (проверено: builder спавнится, постройка проходит после 40с стресса).
3. **`Space` у здания = сколько оно занимает из `MaxBuildings` (50)**, НЕ грид-футпринт.
   House Space=3 → CurrentBuildings +3. Windmill Space=1. Замок Space=0. ✅
4. Все 12 supply называются одинаково `"Supply"` → `FindFirstChild("Supply")` вернёт первую;
   итерируй `:GetChildren()` и фильтруй по позиции/`Occupied`. ✅
5. Перед постройкой ставить `PlayerFolder[me].Building.Value=true` и `.CanPlace.Value=true`
   (клиент так делает, сбрасывает Building в false ПОСЛЕ выстрела). ✅ держал true — проходит.

---

## 1. Карта / координаты (MapName: Undersplit)

| Точка | Позиция | Статус |
|---|---|---|
| Мой замок (Castle.Hitbox = PrimaryPart) | **(-26.812, 1.650, -41.983)** | ✅ |
| Спавн персонажа (King) | ~(-24.3, 3.2, -42.0), у замка | ✅ |
| Враг (бот, red, TeamColor 0.831,0.306,0.314) | королевство в +X/+Z, замок есть | ✅ |
| `workspace.backup` | стартовая CFrame, куда телепортит Program | ✅ |

**Supplies (фермы под виндмиллы) — `workspace.Game.Map.Map.Supplies` (12 шт, все Name="Supply"):** ✅
- Свободные у МОЕГО замка: **(-23.106, -42.854)** и **(-30.394, -40.543)** (Y≈0.28). ← мои виндмилл-споты
- (-23.106,-42.854) уже занят моим виндмиллом (Occupied=true). ✅
- Свободные далеко (нужен Outpost/территория): (13.34,-35.39), (37.93,-34.78), (54.55,-15.38).
- Занятые врагом/нейтралами: (18.5,43.9),(28.1,41.3),(26.9,27.6),(-15.3,36.0),(-42.1,30.5),(-56.5,8.3),(-27.9,-27.2).

Грид: интовые ячейки 1 студ (см. атрибут `OccupiedCells` замка — JSON массива {x,z}). Замок занимает x∈[-29..-24], z∈[-44..-40].

---

## 2. Remote-сигнатуры (`game.ReplicatedStorage`, 119 remote)

### Рабочие (подтверждены вживую)
| Remote | Тип | Аргументы | Делает | Статус |
|---|---|---|---|---|
| **PlacementEvent** | Event | `(name:string, pos:Vector3, math.rad(rot):number, wallTargetB_or_nil, supplyModel_or_nil)` | Ставит здание `name` в позицию `pos`. **pos.Y = groundY + hitboxH/2 + 0.02!** Для Windmill 5-й арг = ближайший свободный Supply (≤4 студа). | ✅ |
| **Spawn** | Event | `(unitName:string, primaryPart:BasePart)` | Рекрут юнита у здания. `Spawn:FireServer("Builder", castle.PrimaryPart)` → +1 Builder ✅. Военные — только из своего здания (Knight из замка ❌, нужен Barracks). | ✅ |
| **SendUnitGoals** | **Function** | `:InvokeServer(goals, attackTargetOrFalse, true?)` где `goals = {{unitModel, targetPos:Vector3}, ...}` | Приказ юнитам идти/атаковать. `false` = просто move (юниты сами бьют врага в радиусе по пути). Вернул table, юниты реально пошли в точку ✅. | ✅ |
| **ChangeIdleState** | Event | `(idle:boolean)` | `false` = я активен (реклейм королевства у бота); `true` = я AFK (клиент шлёт сам). | ✅ |
| Command | Event | `(t1,t2,t3,t4)` — ЭТО ЧАТ-команды (split сообщения), НЕ приказ юнитам | чат-команды | ✅ (не юниты) |
| Sell | Event | ⚠️ `(buildingModel?)` | продать выделенное (клавиша L) | ⚠️ |
| Upgrade | Event | ⚠️ `(buildingModel?)` | апгрейд (клавиша C) | ⚠️ |
| ThrowSpell | Event | ⚠️ `(spell:string, pos:Vector3)` | кинуть спелл | ⚠️ |
| StartResearch | Event | ⚠️ `(category, tier, place)` | старт ресёрча | ⚠️ |
| PlaceWall / OpenWall | Event | ⚠️ | стены | ⚠️ |
| BuySpell / BuySkin / BuyEffect | Event/Func | ⚠️ | покупки | ⚠️ |

### Read-only / клиентский фон 🔇
GetInfoCash (Invoke → текущий кэш; 0 если моей папки нет), SendMoneyInfo2 (push кэша в u11),
AddCoinsClient (попап "+N coins"), FetchDataToClient, GetSettingsToClient, GetResearchedClient,
GetCachedDataFromClient, GetSettingsCachedClient, UpdateTargetsClient, PathsCurrentlyExist,
BuildEffect (входящий: показывает чьё здание строится — спалил билд-ордер врага: House→Builder Hut→Outpost),
Trainingbar, CreateShootBeam, EffectEquippedClient, EquippedClient, GetServerType, SendUnitGoals(Func).

Полный список остальных remote снят (119), не критичные опущены — добивать спаем по мере надобности.

---

## 3. Дерево объектов

- **`workspace.Game`**: Map, PlayerFolder, BotsEnabled(BoolValue=true ← включает AFK-латч),
  Gamemode("SINGLEPLAYER"), Intermission(false), MapName, Ranked, GameTime, Wave, Limits,
  PrivateServerOwner(""), isNewPlayerMatch.
- **`workspace.Game.PlayerFolder`**: по папке на слот (7). Моя = **"godlimaster11"** (TeamColor 0.745,0.384,0.176 — оранж/коричн).
  - Дети моей папки: `Buildings`(модели зданий), `Units`(King + Builder'ы), `Stats`(value-папка),
    `Building`(Bool — режим стройки), `CanPlace`(Bool), `PreviewPart`, `TeamValue`/`TeamColor`(+Perm),
    `Finished`, `Target`, `Allies`.
  - `Stats`: MaxBuildings=50, CurrentBuildings, MaxUnits=30, CurrentUnits, CashPerMin.
- **`workspace.Game.Map.Map.Supplies`** — 12 моделей Supply (атрибут `Occupied`).
- **`ReplicatedStorage.Buildings`** — папки-скины (Default, Mossy, Golden, ...). Реальные модели в **`Buildings.Default.*`**.

---

## 4. Экономика

- Кэш капает раз в `RateFarm`(=60) от каждого здания с `GiveCash`. HUD "X (N/m)" = N в минуту.
- **Замок**: GiveCash=20/мин, Range=12, AddBuildings=50, HP 250, Space=0.
- **Windmill** (Cost **10**): GiveCash **15/мин**, нужен свободный Supply, Space=1, HP25. ← главный фарм-юнит, дешёвый. ✅
- Кэш приходит через SendMoneyInfo2/GetInfoCash (read-only) — фейкнуть нельзя, надо реально строить.

### Каталог зданий `Buildings.Default` (Cost / эффект / Space / hitboxH для Y) ✅
| Здание | Cost | Эффект | Space | hitboxH (Y=g+H/2+.02) |
|---|---|---|---|---|
| Windmill | 10 | +15$/мин (нужен Supply) | 1 | 2.212 |
| House | 60 | +20 MaxUnits | 3 | 1.907 |
| House2 | 75 | +15 MaxUnits | 7 | 1.907 |
| Builder Hut | 35 | +20 MaxBuildings | 0 | 1.174 |
| Outpost | 100 | +20 MaxBuildings, Range 10 (террит.) | 0 | 4.091 |
| Castle | 100 | +20$/мин, +50 builds, Range12 | 0 | 3.044 |
| Stables | 40 | конница | 5 | 2.347 |
| Barracks | 45 | пехота | 5 | 1.778 |
| Tower | 20 | dmg1 rng9 | 8 | 3.372 |
| Tower2 | 35 | dmg5 rng7 | 3 | 3.646 |
| Watchtower | 60 | dmg8 rng9 | 8 | 3.119 |
| Trap | 25 | dmg500 (Ground) | 3 | 0.642 |
| Water Trap | 20 | dmg100 (WalkGround) | 1 | 0.877 |
| Market | 150 | RateFarm | 5 | 1.344 |
| Port | 55 | вода | 5 | 2.058 |
| Spell Factory | 130 | спеллы, rng80 | 5 | 0.891 |
| Armory | 175 | — | 5 | 2.274 |
| Siege Workshop | 120 | осада | 5 | 1.858 |
| Hospital | 125 | хил rng5 | 5 | 1.576 |

### Каталог юнитов `Units.Default` (Cost / Dmg / HP / Range / Speed / Space) ✅
Рекрут: `Spawn:FireServer(unitName, building.PrimaryPart)` — building.PrimaryPart = `building.Hitbox`.
**ВАЖНО: есть задержка тренировки** — юнит появляется в `Units` через несколько сек после Spawn (атрибут `Time`),
не проверяй сразу. Здание должно быть `Built==true`/`Finished`. Knight из Barracks ✅ (появились через ~10с).
Рекрут-здания: Castle, Barracks, Stables, Port, Siege Workshop, Hospital, Spell Factory, Market (Armory→ресёрч).
Замок рекрутит только Builder/базовых; Knight НЕ из замка ❌ (нужен Barracks). Атрибут `Type`=Small/Big — это РАЗМЕР
юнита (для транспорта/формации), НЕ здание. У каждого здания свой набор юнитов (RecruitList строится при выборе).
| Юнит | Cost | Dmg | HP | Range | Spd | Space | прим. |
|---|---|---|---|---|---|---|---|
| Builder | 10 | 0 | 10 | 6 | 2.3 | 1 | строит/чинит, из замка ✅ |
| King | 0 | 0 | 60 | 6 | 2.4 | 0 | герой, всегда есть |
| Shieldman | 15 | 0 | 50 | 0 | 2.8 | 1 | танк-щит |
| Swordman | 15 | 2 | 15 | 2 | 2.7 | 2 | дешёвый меле |
| Spearman | 20 | 1 | 15 | 3 | 2.6 | 2 | анти-кав |
| Knight | 25 | 2.5 | 30 | 2 | 2.6 | 2 | основной меле ✅(нужен Barracks) |
| Archer | 20 | 1 | 13 | 5 | 2.3 | 3 | стрелок |
| Crossbower | 40 | 4 | 15 | 6 | 2.3 | 3 | стрелок+ |
| Longbower | 35 | 2 | 15 | 8 | 2.3 | 3 | дальний |
| Medic/Repairman | 30 | 0 | 20 | 4/6 | 2.3 | 1 | хил юнитов/зданий |
| Battering Ram | 120 | 10 | 220 | 3 | 1.6 | 4 | таран по зданиям |
| Ballista | 100 | 15 | 30 | 9 | 1.3 | 10 | осада |
| Catapult | 150 | 8 | 30 | 7 | 1.3 | 12 | осада-сплеш |
| Trebuchet | 400 | 30 | 50 | 15 | 1.3 | 30 | топ-осада |
| Wizard | 50 | 3 | 20 | 4 | 2.3 | 4 | маг-сплеш |
| Horses (Basic/Fast/Strong) | 10/20/25 | 0 | 25/30/60 | 5 | 3/4/3 | 0/1/1 | маунт (hasUnits) |
| War Wagon | 55 | 0 | 125 | 5 | 1.3 | 4 | возит юнитов |
| Bandit | 25 | 0 | 13 | 7 | 3.5 | 0 | ворует кэш (hasMoney) |
| Fishing Boat | 15 | 0 | 20 | 0 | 3 | 0 | +кэш на воде (RateFarm,GiveCash) |
| Ships (Attack/Battle/Transport/Ferry) | 40/200/30/35 | … | вода |

---

## 5. Анти-чит / серверные проверки

### AFK-латч (КРИТИЧНО) — разобран по декомпилу `PlayerScripts.Program` (стр. 422–458) ✅
- `u49 = os.time()` — время последнего ввода. Обновляется ТОЛЬКО реальными `UserInputService.InputBegan/InputChanged` (engine input). Мои execute-телепорты u49 НЕ трогают.
- `u52` = порог: **30 сек** первые 200 сек матча, дальше **100 сек** (`task.delay(200, ...)`).
- Цикл `while task.wait(2)`: если `workspace.Game.BotsEnabled.Value` и `u49+u52 < os.time()` →
  `ChangeIdleState:FireServer(true)` (отдаёт королевство боту). Когда снова актив → шлёт `false`.
- **Реклейм:** `ChangeIdleState:FireServer(false)`. Но клиентский цикл снова шлёт `true`, пока u49 несвежий.
  ❌ VIM (mouse-move/key) u49 НЕ обновляет при расфокусе окна → не работает через MCP.
  ✅ **Рабочий гард:** луп раз в 0.4с: `workspace.Game.BotsEnabled.Value=false` (клиент-сайд — цикл пропускает
  весь idle-блок, `true` не шлётся) + `ChangeIdleState:FireServer(false)` (реклейм). Сервер BotsEnabled обратно
  не переписывает в этом матче → держится. Это и есть анти-афк для автофарма.
- При перехвате ботом: твои Units пропадают/перетекают боту, `Spawn`/`PlacementEvent` молча падают. Контроль-тест —
  `Spawn:FireServer("Builder", Castle.PrimaryPart)`: если билдер не появился → ты залатчен, чини гард.

### Постройка
- ❌ Y = центр supply (≈0.2–0.28) → отклоняется молча (без алерта, кэш не списан).
- ✅ Y = groundY + hitboxHeight/2 + 0.02; `Building.Value=true`, `CanPlace.Value=true` перед выстрелом.
- Кэш списывается только при успешной постройке (cost). MaxBuildings лимит = сумма Space ≤ 50.
- Позиция в X,Z — сырой raycast-хит (НЕ снап на инты), сервер сам считает ячейки.

---

## 6. Кейбинды и клиентская логика (из Program/настроек) ✅
upgrade=C, sell=L, interact=Q, teleport=T, formation=F, backtocastle=N, reveal=Z,
buildingsvisibility=V, unselect=E, marker=Y, playerlist=Tab, multipleprim=LeftControl, multipleseco=LeftShift.
- Превью-постройка: ротация колесом (`u29 += 3`, `math.rad(u29)`); позиция = raycast от мыши.
- Program автотелепортит перса на (Castle.X, Castle.Y+6, Castle.Z) на старте.

---

## 7. Полный рецепт постройки (готовый код-шаблон) ✅
```lua
local rs = game:GetService("ReplicatedStorage")
local pf = workspace.Game.PlayerFolder[lp.Name]
local function place(name, x, z, hitboxH, supplyModel, rotDeg)
  rs.ChangeIdleState:FireServer(false)
  pf.Building.Value = true; pf.CanPlace.Value = true
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  rp.FilterDescendantsInstances = {pf, workspace.TargetFilter, workspace.Game.Map.Map.Supplies}
  local hit = workspace:Raycast(Vector3.new(x,50,z), Vector3.new(0,-100,0), rp)
  local gy = hit and hit.Position.Y or 0.2
  local pos = Vector3.new(x, gy + hitboxH/2 + 0.02, z)
  rs.PlacementEvent:FireServer(name, pos, math.rad(rotDeg or 0), nil, supplyModel)
end
```

---

## 8. Автофарм (готов, проверен вживую)
Скрипт: `Средневековый матч RTS.lua` (рядом). Премиум-GUI (Violet-Noir), draggable, unload-кнопка.
Тоглы: Авто-мельницы / Авто-экономика (дома+хижины по нехватке кэпа) / Авто-строители / Авто-армия
(Barracks+рекрут до кэпа) / Авто-защита (юниты на врага у замка) / Раш. Анти-AFK всегда вкл (BotsEnabled=false).
Проверено: GUI поднялся, BotsEnabled держится false под нагрузкой, Knight 4→10 (авто-армия),
**MaxUnits 50→70 — авто-экономика сама поставила House** (значит place() через скрипт реально строит), unload чистит всё.
- Лимиты: у каждого типа здания свой кап (видел алерт **"дозволено только 25 этого блока"**) — скрипт переживает отказ (placeVerify вернёт false).
- Рейт-кап remote зашит (maxRemotePerSec, по умолч. 120; анти-AFK ~2.5/с) — суммарно сильно < 400/с.
- Дальние supply territory-gated: для них нужен Outpost-чейн (в скрипт не зашит автоматический дальний захват — только reachable supply).

## Итоги матча (контекст)
Этот матч проигран по армии: вражеский бот раздулся до ~73 юнитов, пока чинил анти-AFK. Замок цел (250 hp),
экономика 50/м, но воевать поздно. Все механики сняты и проверены — автофарм рабочий для следующих матчей.

---
---

# РАЗБОР ЛОББИ + ДАННЫЕ ИЗ ИСХОДНИКОВ (сессия 2 — статический реверс из лобби)

> Стартовали из **ЛОББИ** `PlaceId 10853515606` (v5300, «Средневековая стратегия в реальном времени»),
> персонажа нет. **Лобби-плейс содержит ВЕСЬ матч-RS** (134 RemoteEvent + 42 RemoteFunction, папки
> `Utilities/Buildings(23)/Units(27)/Spells(4)/Lobby/Maps`), плюс лобби-хаб крутит фоновый **bot-vs-bot
> демо-матч** в `workspace.Game.PlayerFolder` — на нём снято живое поведение бота.
> **Матч-плейс = `13802699692`** (reserved). Туда телепортит сервер через TeleportService.
>
> ВАЖНО: in-match контроллер `PlayerScripts.Program` (шлёт Spawn/PlacementEvent/Upgrade/Sell/Command/спеллы/
> транспорт) в лобби НЕ загружен и GC'нут → точные `:FireServer` арги этих ремоутов **не читаются из
> исходника**, помечены ⚠️ needs-live. Зато ВСЕ data-модули и весь лобби-флоу читаются → помечены ✅(src).
> Легенда: ✅(src) = прочитано из исходника модуля/лобби-скрипта · ⚠️ = needs-live (добить в матче).

## 9. Лобби → матч → реджойн (✅ src: `LobbyClient` 1951 строк + `ReplicatedStorage.Lobby.*`)

**ВХОД В МАТЧ (главная точка):** `ReplicatedStorage.Lobby.Play:FireServer(mode)` — создаёт/входит в комнату
режима; сервер сам телепортит когда комната заполнена. **SINGLEPLAYER заполняется 1/1 → мгновенный старт.**
```lua
game.ReplicatedStorage.Lobby.Play:FireServer("SINGLEPLAYER")  -- ✅ src (call sites L115/893/929)
-- дальше сервер сам: JoinServerClient → StartTeleportClient(loading) → TeleportService → place 13802699692
```
Гейт по уровню (мой Level=**1**): мультиплеер с **lvl≥6** (`MatchmakingTab.Lock` "REACH LEVEL 6"),
**RANKED с lvl≥8** (не 7!). Ниже 6 — только **SINGLEPLAYER**.

| Mode | игроков на старт | гейт |
|---|---|---|
| SINGLEPLAYER | 1 (инстант) | нет |
| 1v1 / 2v2 / 3v3 | 2 / 4 / 6 | нет (но UI с lvl<6 скрыт) |
| CLASSIC / FFA / BLITZ / SURVIVAL | 6 | lvl≥6 |
| RANKED | 4 | lvl≥8 |
| FOG | 6 | только private/testing |

**Прочие лобби-ремоуты (✅ src, под `Lobby.`):**
- `JoinNewPlayerQueue:FireServer()` — авто-очередь новичка.
- `ServerInteraction:FireServer(join:bool, isPublic:bool, name?)` — `(true,true,name)` войти в листинг / `(false,false)` выйти из комнаты.
- `CreatePrivateServer:FireServer(isPrivate, isTesting, gamemode)`, `JoinPrivateServer:FireServer(code, isTesting?)`.
- **Реджойн:** `token = Lobby.GetRejoinPrompt:InvokeServer()` (→ token, _, isPrivate) → `Lobby.AcceptRejoin:FireServer(token)`. Сервер телепортит назад. (2-я точка: token из `FindFriend:InvokeServer(userName)`.)
- Server→client: `StartTeleportClient()` (старт телепорта, loading), `JoinServerClient(name,gamemode)`, `TeleportFailedClient`, `KickedClient("server"/"party")`, `CreateQueueButton(...)`, `UpdateRooms(...)`.

**Детект конца матча (⚠️ payloads needs-live, instances ✅):** `EndGameClient.OnClientEvent` = главный сигнал
конца+победитель; `ChangeEndGameRewards` = таблица наград (coins/xp/trophy); `RestartClient` = возврат в лобби.
Win-condition BindableEvent `OutpostDestroyed` + флаг `Castle.Destroyed=true`. Авто-цикл матчей: ловить
`EndGameClient` → ждать `RestartClient`/телепорт в лобби → снова `Play:FireServer(...)` или AcceptRejoin.

## 10. Голосование карты и спавн (✅ src: `Utilities.Voting`)

Поток на старте матча, фаза различается **3-м (bool) аргом `StartVoting`**:
- Map-vote: `StartVoting:FireAllClients(options[], 15, false, 15)`; `Values.VotingProgress=true`.
  Голос: **`PlaceVote:FireServer(order)`** (order=`.order` опции; в этом билде только order=**1**, т.е. карта одна
  случайная — выбрать нельзя). Сервер: апдейт `UpdateVotingSystem:FireAllClients(options)`.
  ⚠️ Рейт-лимит: >100 PlaceVote/сек → Kick("abusing 003"). Геймпасс 88442787 → голос ×2.
- Reveal/spawn: `StartVoting:FireAllClients(mapName, 15, true, t)`; `VotingProgress=false`.
  Спавн: **`ChangeSpawn:FireServer(spawnID)`** (spawnID = атрибут `ID` "1".."4" на `RandomSpawn`).
  Дебаунс 0.2с/игрок (~5/с), первый занял — чужой ID отклоняется → **хватать рано**. Апдейт `UpdateChangeSpawn`.
- **Спавн-селект только для `3v3`/`2v2`/`RANKED`** (`workspace.Game.Gamemode`). SINGLEPLAYER/прочие casual →
  сервер сразу `return {map}` без выбора спавна.

**3 карты (✅ instances):** Volcano (4 spawn, **40** supply, 0 fishing) · Shortwalk (4 spawn, **20** supply,
4 fishing) · Saples (4 spawn, **27** supply, 4 fishing). Каждый `RandomSpawn` имеет атрибуты `ID`("1".."4") и
`Team`("1"/"2"). Журнальный «Undersplit» — видимо старое имя/матч-специфичная.

## 11. Дерево ресёрча (✅ src: `Utilities.ResearchInfo`, хост = **Armory** Cost 175)

Структура `ResearchInfo[Category]` = массив **тиров** (порядок = пререквизит, серверный гейт ⚠️), entry =
`{Cost, Name, Image, Description}`. **Поля Duration/Time НЕТ** — длительность ресёрча серверная ⚠️.
Старт ⚠️: `StartResearch:FireServer(researchName)` (инфер; точные арги live). Запрос: `GetResearchedClient:InvokeServer()`. Конец: `ResearchEnded.OnClientEvent`.

| Категория | Тир | Name | Cost | Эффект |
|---|---|---|---|---|
| Melee | 1 | LessSplash | 75 | меле −50% сплеш-урона |
| Melee | 2 | ThrowSpears | 125 | копейщики метают копья (+3 range) |
| Melee | 2 | ShieldmanThorns | 150 | щитовики отражают 50% урона меле |
| Ranged | 1 | MoreRange | 75 | лучники/арбалет/лонгбоу +1 range |
| Ranged | 2 | ArchersBounty | 200 | +25$ за убитый объект (стрелки) |
| Ranged | 2 | FireArrows | 600 | огненные стрелы 3 dps/6с |
| Siege | 1 | **Balloon** | 75 | **разблок юнит Balloon** |
| Siege | 2 | BalloonBombs | 400 | шары бомбят здания |
| Siege | 2 | GroundTraps | 150 | видеть наземные ловушки |
| Siege | 3 | HouseLimit | 200 | +1 лимит House |
| Siege | 3 | SiegesExplode | 200 | осада взрывается при смерти |
| Naval | 1 | **Siege Ferry** | 75 | **разблок юнит Siege Ferry** |
| Naval | 2 | WaterTraps | 150 | видеть водные ловушки |
| Naval | 2 | ShipsBounty | 150 | +30$ за убитый объект (флот) |
| Naval | 3 | ShipsExplode | 125 | флот взрывается при смерти |
| Naval | 3 | **Battle Ship** | 300 | **разблок юнит Battle Ship** |
| Magic | 1 | FasterSpells | 75 | время варки спеллов ÷2 |
| Magic | 2 | LifeSteal | 300 | маг реген 50% HP после убийства |
| Magic | 2 | TeamSwitch | 400 | каждый 3-й убитый магом враг → к тебе |

**Гейтинг юнитов = 2 слоя:** (1) здание (см. §14) — единственный гейт для большинства, **Knight гейтится
ТОЛЬКО Barracks, НЕ ресёрчем** (вот почему в прошлой сессии он «не зашёл» из замка). (2) ресёрч добавляет
3 юнита поверх здания: Balloon (Siege Workshop+ресёрч75), Siege Ferry (Port+75), Battle Ship (Port+300).

## 12. Апгрейды зданий (✅ src: `Utilities.UpgradeInfo`, **max tier = 2**, клавиша C)

Только **6 зданий** апаются (есть модель `<Name>2`), атрибут `UpgradeIndex` 0→1. Апгрейд ⚠️: `Upgrade:FireServer(...)` (инфер: либо без аргов по выделению, либо (model)/( {models} ); live). Эффективные lvl2-статы — серверные ⚠️ (шаблоны `<Name>2` противоречивы, не верить).

| Здание | Cost апгрейда | Эффект |
|---|---|---|
| Castle | 120 | +урон, +HP |
| Hospital | 100 | лучше хил, +HP |
| Watchtower | 50 | +урон, +HP |
| House | 50 | лимит юнитов ×1.5, +HP |
| Tower | 35 | +урон, +HP |
| Windmill | 25 | деньги ×1.5, +HP (бот качает именно их: GiveCash 15→23) |

**Sell ⚠️** (клавиша L): `Sell:FireServer(...)` — рефанд серверный, % неизвестен. `CastleSellAsk` —
отдельный гейт-подтверждение для продажи замка. Всё needs-live.

## 13. Спеллы (✅ src: `Utilities.ObjectStats` + `Effects` VFX-хендлер)

Требует **Spell Factory** (Cost **130**, `Range=80` = радиус каста от фабрики). Спеллы «варятся» как юниты
(в Recruits фабрики), хранятся, потом кидаются. `Range` поля = **радиус AOE** (диаметр круга = Range×2),
`Time` = длительность эффекта (НЕ время варки — варка серверная, ÷2 ресёрчем FasterSpells 75).

| Спелл | Cost | Range(AOE Ø) | Time | Урон/эффект |
|---|---|---|---|---|
| Earthquake | 20 | 10 (Ø20) | 10с | dmg1 + стан, **только здания** |
| Heal | 50 | 7 (Ø14) | 8с | +4 HP/тик союзникам |
| Rampage | 100 | 6 (Ø12) | 12с | +скорость и +rate юнитам в зоне |
| Lightning | 150 | 3 | 8с | dmg25 сплеш, **~5с телеграф** (бьёт двумя `CreateSpellEffect`: warn→strike), **не бьёт замок** |

Каст ⚠️: `ThrowSpell:FireServer(spellName, pos)` (инфер, бьётся с `CreateSpellEffect(owner,name,pos,isStrike)` ✅).
Варка ⚠️: `BuySpell:FireServer(spellName, factory?)`. HUD: `SpellButtonClient`/`ChangeSpellsClient` (server→client).

## 14. Рекрут-листы по зданиям (✅ src: `Utilities.ObjectStats[Building].Recruits`, train **10с** всем)

Рекрут ⚠️: `Spawn:FireServer(...)` (журнал: `(unitName, building.PrimaryPart)` ✅ verified live прошлой сессией).
Очередь: `QueueClient:FireClient(player, building, unitName, isAdd:bool)` ✅ src. `Trainingbar`/`GetRecruitingBar`/
`Recruited`/`UnitSpawnClient` — фидбек прогресса.

| Здание (Cost) | Рекрутит (Cost) |
|---|---|
| **Castle** (100) | Builder 10, Archer 20, Swordman 15, Repairman 30, **Bandit 25** |
| **Barracks** (45) | **Knight 25**, Crossbower 40, Shieldman 15, Spearman 20, Wizard 50, Longbower 35 |
| **Stables** (40) | Basic Horse 10, Fast Horse 20, Strong Horse 25 |
| **Port** (55) | Transport Ship 30, Siege Ferry 35*, Fishing Boat 15, Battle Ship 200*, Attack Ship 40 |
| **Siege Workshop** (120) | Ballista 100, Balloon 50*, Battering Ram 120, Catapult 150, Trebuchet 400, War Wagon 55 |
| **Hospital** (125) | Medic 30 |
| **Spell Factory** (130) | 4 спелла (через BuySpell, не Spawn) |
| **Armory** (175) | — (только ресёрч) |
`*` = locked до ресёрча (см. §11). Замок рекрутит и базовых меле/стрелков → можно армию начать без Barracks,
но Knight (HP30 vs Swordman HP15) — только Barracks.

## 15. Полный каталог юнитов (✅ src: `Utilities.ObjectStats`, 27 шт) — уточнения к §4

Rate = интервал действия в сек (меньше=быстрее). Спецфлаги: **King** (Cost0, HP60, аура +50% урон агрессивным /
+50% work-speed пассивным в Range 6; «если умрёт — ничего»). **Bandit** (HP13, Spd3.5, Space0, **невидим пока
hasMoney=false**, крадёт 25% кэша замка с Range7). **Fishing Boat** (GiveCash15, RateFarm60, на fishing-споте,
1/команда/спот). Транспорт-вместимость (серверная, из тултипа, НЕ поле Space): Transport Ship **12** (норм юниты,
занятые кони игнор), War Wagon **4** (юниты бьют изнутри), Siege Ferry **2** (осада), Balloon **8** (воздух, мимо
меле/воды/сплеша), Кони — 1 всадник. **PermDamage** — вторичный серверный атрибут (база урона для буфов King/Rampage).
Анти-балон (бьют по воздуху): Archer/Crossbower/Longbower/Ballista. Анти-кав: Spearman (ваншот коней). Танки:
Shieldman (HP50, ×0.3 урон от стрел), Battering Ram (HP220, только здания), Battle Ship (HP110).

## 16. Доп. экономика (✅ src: `MarketInfo` / `BenefitInfo` / `ObjectStats`)

- **Market** (Cost150) сам не даёт; инвест ⚠️ `Invest:FireServer(marketModel, type)`:
  Wheat 75→125, Wood 150→250, Metal 300→500 — все **+66.7% за ~90с** (ROI линейный, тиры лишь масштаб).
- **Fishing** ⚠️ `Fishing:FireServer(boat)` — тоглит `Fishing=true`, +15$/тик пока на синем `FishingSpot`.
- **Bandit** ⚠️ `BanditSteal:FireServer(bandit)` — у замка врага (Range7), Q → −25% его кэша, вернуть в свой замок;
  видим/уязвим после кражи (`hasMoney=true`). VFX `BanditMoneyEffect`.
- **Benefits** (одноразовые матч-анлоки за кэш, гейтят рекрут; покупка ⚠️ — нет читаемого buy-ремоута,
  только `BenefitClient` server→client): See Traps 50, Siege Ferry 100, Balloon 125, Builder Hut 250, House 350,
  Battle Ship 500, Fire Arrows 800.
- Транспорт ⚠️ (Q-interact): `WagonUnits`/`FerryUnits`/`HorseUnits`/`BalloonUnits :FireServer(...)`. У Transport
  Ship своего ремоута НЕТ — грузится через один из этих или Command/Action (live).

## 17. Мета-прогресс и коины (✅ src: лобби-скрипты) — что автоматизируемо

- Скины/эффекты — **косметика, статов не дают** (BuySkin/BuyEffect/EquipSkin :InvokeServer(instance)→bool, сервер
  валидирует). Цены: `SkinCosts.getSkinCost = base[skin]*mult[pack]*(0.7 если Discounted)`. Мульт 0 = некупибельно за коины.
- **Daily** — `GetDailyInfo:InvokeServer()`→(challenges, reset, rewardModel); **15 коинов/челлендж**, прогресс
  серверный (просто играй), claim-ремоута нет.
- **Mastery** — `GetMasteryInfo`/`MasteryClaim` ⚠️ (хендлер GC'нут): даёт ли **in-match бонус** или только коины/скины — НЕИЗВЕСТНО, проверить live (потенциальный буст).
- **RewardedAd:FireServer(1/2)** → `CreateAdReward:InvokeServer()`→коины (за реальную рекламу; проверить, минтит ли без неё).
- **`GiveCoins:FireServer(userId, amount)`** (amount "1000"/"2500"/"5000"/"7500"/"Tournament"/"Clan") — **админ-тул**
  CoinGiverUI, в корне RS. Почти точно админ-гейт. НЕ трогал (read-only). Один live-проб на отказ допустим.

## 18. ⭐ ИИ БОТА И КАК ЕГО ПОБЕЖДАТЬ (✅ снято с живого демо-матча в лобби-хабе)

Решающий цикл бота — серверный (биндблы `*UnitBot` нечитаемы), но снято **живое состояние 4 ботов** (~6 мин):
- **Инварианты:** всегда ровно **3 Builder + 1 King**. Ордер: **Castle → масса Windmill (3–7) → Barracks →
  1 утилити** (House/Outpost/Port/Tower/Builder Hut). Таргет реактивный (Target=nil в покое).
- **ПОТОЛОК ТЕХА (главная слабость):** бот **НИКОГДА** не строит Stables / Siege Workshop / Armory / Hospital /
  Market / Spell Factory / Watchtower / **стены** / **ловушки** / Bandit. Армия — только Barracks-тир
  (Swordman/Archer/Shieldman/Spearman + изредка Knight ×2). **Замок не качает** (всегда 250 HP, index 0; качает
  только Windmill 15→23). **Нет осады** → твою базу пробить не может.
- **Реактивный таргет, нет постоянной агрессии.** Снежный ком в твою пользу: бот масштабируется лишь числом
  тех же дешёвых юнитов и Windmill — новый тир не открывает никогда.

**ПЛАН ПОБЕДЫ (билд-ордер):**
1. **0–3 мин — догнать экономику:** спам Windmill (Cost10, на Supply), 3 билдера заняты, дома под кэп.
2. **3–6 мин — обогнать по теху (бот стоит на Barracks):** **Crossbower(Rng6)/Longbower(Rng8)** обгоняют
   ботского Archer(Rng5) → выигрывают каждый размен бесплатным кайтом; +Wizard (сплеш+стан по блобам); 1–2 Knight фронт.
3. **Оборона лейна:** Wall + Outpost/Watchtower + **Trap(Dmg500)** — у бота нет тарана/требушета, push глохнет.
   Качай свой замок (он свой не качает).
4. **Осада замка:** **Trebuchet (Rng15 > замок Rng12)** бьёт извне радиуса, или Catapult/Ballista + Battering Ram
   (HP220) танк под огонь. 250-HP некачанный замок падает быстро. Перед пушем — Bandit украсть 25% банка.
5. **Тайминг:** коммить раш замка при критмассе осады + ранний экран (обычно ~5–7 мин).

## 19. ЧЕКЛИСТ needs-live для следующей фазы (в матче 13802699692, спай→действие→проверка)

- [ ] **Order-канал:** журнал ✅ `SendUnitGoals:InvokeServer(goals,false,true)` (verified прошлой сессией). Агент
      из лобби его НЕ нашёл и предположил `Command` — РАЗРЕШИТЬ конфликт live (SendUnitGoals скорее всего матч-онли,
      существует; Command — проверить, что это). Автофарм пока юзает SendUnitGoals (верный путь).
- [ ] Точные арги: `Upgrade`, `Sell`, `CastleSellAsk`, `StartResearch`, `ThrowSpell`, `BuySpell`, `Invest`,
      `Fishing`, `BanditSteal`, `WagonUnits/FerryUnits/HorseUnits/BalloonUnits`, подтвердить `Spawn`/`PlacementEvent`.
- [ ] Эффективные lvl2-статы 6 зданий; рефанд Sell %; длительность ресёрча; вместимость транспортов; King-аура %.
- [ ] Payloads `EndGameClient`/`ChangeEndGameRewards`/`RestartClient` (детект конца+победитель+награды).
- [ ] Mastery: даёт ли in-match бонус. `GiveCoins` — один проб на админ-отказ.

---
---

# СЕССИЯ 3 — ЖИВАЯ ВЕРИФИКАЦИЯ В МАТЧЕ (вошёл через лобби, играл SINGLEPLAYER)

> Вход: `Lobby.Play:FireServer("SINGLEPLAYER")` → мгновенный телепорт в матч-плейс `13802699692`
> (jobId меняется, executor сам переподключается ~10–15с, clientId новый). Назад в лобби:
> `TeleportService:Teleport(10853515606)`. Карты SINGLEPLAYER: видел **Seashore** и **Deserted**
> (помимо лобби-троицы Volcano/Shortwalk/Saples — матч-плейс имеет свои карты).

## 20. In-match firing-сигнатуры (✅ ВСЕ из исходника контроллеров, грузятся в матче)

`Program`/`Recruiting`/`Selection`/`UnitUI`/`SpellsClient`/`ResearchClient`/`VotingClient`/
`UnitClientMoveFormation` читаются ТОЛЬКО в матч-плейсе (в лобби GC'нуты). Точные вызовы:

| Remote | Сигнатура (✅ из src + спай) | Прим. |
|---|---|---|
| **Spawn** | `:FireServer(unitName, building.PrimaryPart)` | building.PrimaryPart=Hitbox. ✅спай |
| **PlacementEvent** | `:FireServer(name, pos, math.rad(rot), wallTarget\|nil, supply\|nil)` | ✅спай: Windmill пошёл с `[5]=Supply`. `pos.Y=groundY+hitboxH/2+0.02` |
| **SendUnitGoals** | `:InvokeServer(goals, false/true, true)` | **СУЩЕСТВУЕТ в матче** (в лобби нет). `goals={{unit,pos},..}`. 2-й арг: **false=move, true=attack** (UnitClientMoveFormation L179/356/653) |
| **Upgrade** | `:FireServer({model1,...})` | **ТАБЛИЦА выделения** (Selection L591/599/743). Не один! |
| **Sell** | `:FireServer({model1,...})` | Таблица. Конфирм `Confirmation("Sell N objects? (+$X)")` |
| **StartResearch** | `:FireServer(category, tonumber(tier), tonumber(place))` | ResearchClient L161 (category, № тира, атрибут Place) |
| **BuySpell** | `:FireServer(spellName)` | Recruiting L246 (фабрика по выделению) |
| **ThrowSpell** | `:FireServer(spellName, hit.Position)` | SpellsClient L241. Валидные поверхности: Ground/Shore/WalkGround/Supply/BotPath/Bridge/Slate |
| **Invest** | `:FireServer(marketModel, type)` | type∈Wheat/Wood/Metal (Recruiting L250) |
| **Fishing** | `:FireServer(boatModel)` | UnitUI L38 |
| **BanditSteal** | `:FireServer(banditModel)` | UnitUI L41 |
| **WagonUnits/FerryUnits/HorseUnits/BalloonUnits** | `:FireServer(transportUnitModel)` | UnitUI/Selection — Q-interact load/unload |
| **ChangeSpawn** | `:FireServer(spawn:GetAttribute("ID"))` | VotingClient L136 |

## 21. КРИТИЧЕСКИЕ гочи постройки (стоили кучу времени)

1. **Грунт может быть высоко!** На Deserted поверхность = part `Ground` (parent `GroundModelClient`)
   на **Y≈5.0** (замок Y≈6.45). Любой хардкод `Y < 2.2` в поиске спота → **на такой карте НИЧЕГО не
   строится** (только мельницы на supply работают, т.к. ставятся прямо на supply). ✅ ФИКС: сравнивать
   `math.abs(hitY - castleY) < 6`, не абсолют. Это был главный баг этой сессии (cash копился, зданий ноль).
2. **Outpost: лимит = 1** (`BuildingUI` L813 `Outpost>=1 → нельзя`). Цепочка аутпостов невозможна.
   Плюс особая валидация `nearcastle(folder, cframe, 8, true)` (Hospital/Outpost радиус 8; Spell
   Factory/Trap/Market — 18). Outpost через мой computed-point молча отклонялся.
3. **Открытый грунт ставится через occupied-cell-aware findOpenSpot** (проверяет `OccupiedCells` всех
   зданий). Ручная постановка по «голому» кольцу падает по оверлапу (база тесная). Использовать findOpenSpot.
4. **Площадь застройки = территория замка (range 12) = крошечная и быстро забивается.** Towers
   Space=8 каждая (!) жрут build-cap (2 башни = 16/50). На тесной карте Market негде ставить → экономика затыкается.
5. Здания имеют атрибуты **`Health`/`MaxHealth`** — читать HP замка/врага через `GetAttribute("Health")`.

## 22. ⭐ ПОВЕДЕНИЕ БОТА И ОБОРОНА — ВЕРИФИЦИРОВАНО ВЖИВУЮ

- Бот **пассивен ранние ~15 мин**, копит экономику, потом **атакует массой ~40 юнитов** (всё Barracks-тир,
  меле/стрелки; замок НЕ качает — стоит 250). **Осады у бота НЕТ.**
- **МОЙ ЗАМОК (250 HP) + 2 Tower удержали 40+ юнитов бота на ПОЛНОМ HP неограниченно** — статичная
  оборона (башни) держит базу БЕЗ армии. ⇒ Ключ: поставил башни → армия свободна для атаки.
  `Tower`(20,Space8,dmg1,rng9)/`Watchtower`(60,dmg8,rng9) + замок (dmg10,rng12) перемалывают дешёвое меле.
- Раш сработал: армия (~23) дошла до вражеского замка → **191.5→125 HP**, НО разменялась 23→4 (замок бота
  auto-fire dmg10 rng12 фокусит входящих в упор). Размен невыгодный без range-осады.
- **РЕШЕНИЕ добивания: Trebuchet (range 15 > замок range 12, dmg 30, rate 6)** — бьёт замок ИЗ-ЗА радиуса
  его auto-fire, урона не получает. 250 HP / 30 ≈ 9 выстрелов ≈ 54с соло-килл замка безопасно. Это
  главный юнит-добивашка (Catapult rng7/Ballista rng9 — ВНУТРИ замок-range12, горят). Escort Longbower (rng8).

## 23. Экономика — реальный потолок на territory-gated картах
Castle 20/мин + 2 мельницы (на 2 близких supply) = ~48/мин — и всё, остальные supply вне range, цепочка
Outpost невозможна (лимит 1). Market-инвест — единственный масштабируемый движок, НО негде ставить на
тесной карте. ⇒ Экономику надо поднимать в ПЕРВЫЕ 10 мин (пока бот пассивен и место свободно), потом
застройка забивается. Лучшие карты по supply: Volcano(40) > Saples(27) > Shortwalk(20) > Deserted(мало).

## 24. Автофарм v2 (рабочий, перезаписан) — архитектура
Анти-AFK (BotsEnabled=false + ChangeIdleState, держит) → rate-cap → экономика (builders/мельницы/дома,
**inflight-учёт против overshoot**) → Market-инвест (компаунд) → tech (Barracks→Siege→Stables, гейт «эко
поднята ≥2 Market ИЛИ угроза») → армия контр-составом (Longbower-приоритет) → осада → апгрейды →
**статичная оборона (Towers/Watchtower/Trap при угрозе)** → push (раш когда не-угроза+армия+осада ИЛИ
статич.оборона стоит+армия≥16; при угрозе оборона юнитами держит ДО башен, потом освобождает в раш).
GUI Violet-Noir + телеметрия + unload + reload-guard (`_G.__MRTS_AI_UNLOAD`), `_G.__MRTS=state` для
живого контроля тоглов. Динамический hitbox-H из шаблона (а не хардкод). Файл = `Средневековый матч RTS.lua`.
ОСТАЁТСЯ: Trebuchet в осадный состав; экономику-вперёд на свежем матче (хорошая карта) для чистой победы.

## 25. ✅✅ ПОБЕДА — матч выигран (карта Hashore, SINGLEPLAYER)

**Вражеский замок снесён 250→12.5→0, бот стёрт (0 зданий/0 юнитов), матч → intermission. Мой замок 250
целый весь матч, анти-AFK держал намертво (ни разу не отдал королевство).** Это первая доведённая до конца победа.

**Рабочий билд (что реально сработало):**
- Бот в этом SINGLEPLAYER-инстансе **остался пассивным на ~14 юнитах весь матч** (не раздувал армию). Это окно.
- Экономика: 2 мельницы + замок (~50/мин). Markets/Fishing не использовал (на Hashore гора зажимает место под Market/Port; Siege Workshop тоже не влез — терраин).
- **Ключевой инсайт: против слабого/пассивного бота осада НЕ нужна.** Масса дешёвых **Knight (HP30, Cost25 — танкуют auto-fire замка) + Longbower (range8 — чистят юнитов бота + чипят замок)**. ~16+ юнитов: Knights под огнём замка (замок бьёт 1 юнита/~1.5с — масса переживает), Longbowers добивают. 250-HP замок забит за один заход.
- Push: `SendUnitGoals:InvokeServer(goals, true, true)` (2-й арг true=attack) всей армией на `enemyCastle.PrimaryPart.Position`. Бот 14 слабых юнитов не остановил массу.
- **Sell/Upgrade НЕ работают через прямой `:FireServer({models})`** — сервер требует select-хендшейк (выделение через клиентский Selection), пассинг моделей молча отклоняется. ⇒ В авто их толком не задействовать.
- **Билдеры не строят по близости — нужен ПОСТОЯННЫЙ приказ** `SendUnitGoals` всех билдеров на недострой (иначе здание стоит `Built=false` вечно, как мельница на 8-й мин → половина дохода). Фикс construction-assist: persistent приказ.
- **Terrain блокирует большие здания:** findOpenSpot чек occupiedCells, но НЕ горы/воду; Siege Workshop (большой футпринт) у горы отклоняется. На зажатых картах осаду не построить.

**Итог стратегии-победителя:** анти-AFK (приоритет №1, держит) → 2 мельницы (база эко) → Barracks → **масса Knight+Longbower** → push-всей-массой на замок бота при армии≥16 (без осады, если бот слаб). Замок непробиваем (бот без осады), времени сколько угодно. Когда бот пассивен/мелкий — масса дешёвых юнитов забивает его 250-замок. Автофарм v2 (`Средневековый матч RTS.lua`) это умеет (push-anyway при армии≥16).
