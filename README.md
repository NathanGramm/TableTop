# TableTop

A private 3D virtual tabletop for **Dungeons & Dragons 5th Edition (2014 rules)**, built in
[Godot 4](https://godotengine.org). It's a standalone desktop app: one person hosts (they're the
DM) and friends join over the network.

This first version covers the **turn-based combat engine**: initiative, the full action economy,
attacks, spells, conditions, death saves and the other combat rules. It ships with one pregenerated
character per class, a full character creator, SRD monsters and magic items, and a Homebrew Workshop
for your own monsters, spells and items.

## Running it

1. Download **Godot 4.6 or newer** (the standard version, not .NET) from https://godotengine.org/download.
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button) to play.

### Making a standalone app to send to friends

1. In the Godot editor: **Project → Export…**
2. The first time, click **Manage Export Templates → Download and Install**.
3. Pick **Windows Desktop**, **Linux** or **macOS** and click **Export Project**. You get a single
   `TableTop.exe` (or equivalent). Send it to your friends; nobody else needs Godot installed.

Everyone at the table should run the same build.

## Playing together

- **Host Game**: you become the DM. Share your IP address with your players; the **Table** tab lists
  your local addresses.
- **Join Game**: enter the host's address. Your name decides which characters you control, so
  rejoin with the same name after a disconnect.
- **Play Offline**: solo mode for prepping encounters or testing. You control everything.

Same house or LAN: just join the host's local IP. Over the internet, the host needs **UDP port 24565**
reachable. Try one of these:
- tick *automatic port forwarding (UPnP)* on the host screen (works on many home routers),
- forward UDP 24565 on the router manually, or
- use a free VPN like [Tailscale](https://tailscale.com) or ZeroTier and join with the host's VPN IP.
  This is the easiest option.

The host's game autosaves after every action and reloads next time. **DM → Save…/Load…** keeps named
campaign files.

## How to play

| Control | Action |
| --- | --- |
| Left-click a token | Select it |
| C (or the Character / Spells / Details buttons on the left rail) | Show/hide the character sheet; the rail buttons jump to a page |
| Left-click a blue square | Move there (path and cost shown on hover; opportunity attacks happen automatically) |
| Right-drag | Rotate camera |
| Middle-drag or Shift+right-drag | Pan |
| Mouse wheel | Zoom |
| WASD / arrows, Q / E | Pan, rotate |
| Right-click or Esc | Cancel the current action |
| F | Focus camera on the selected token |

**Character creation**: click **New Character** in the top bar. It walks through the PHB steps with
a live preview, and flags anything that isn't legal yet:
1. Race & class, with level 1–20, dragonborn ancestry, half-elf bonuses and the high elf cantrip.
2. Ability scores: standard array, 27-point buy, 4d6-drop-lowest (rolls are posted to the table log)
   or DM-approved manual entry, plus Ability Score Improvements at your class's levels.
3. Background (12 PHB backgrounds or a custom one) and skills: class picks, half-elf picks, expertise.
4. Class features: fighting style, invocations, metamagic.
5. Equipment: armor you're proficient with (AC preview), shield, weapons.
6. Spells: cantrip and known/prepared limits per class and level, plus always-prepared domain spells.
7. Review.

Players create characters they control; the DM's go to the DM. Use **Edit / Level Up** on the sheet to
level up or rebuild a character outside of combat. Damage taken, used resources, conditions and
notes carry over. **Export…/Import…** saves a character as a `.json` file for other campaigns. The
host checks every character against the same rules, so a modified file can't sneak in an illegal
build. Hit points use the fixed average per level.

**Homebrew Workshop** (DM tab → *Homebrew Workshop…*): make your own content, starting blank or
copying any SRD entry, with a live stat-block preview and rule checks.
- **Monsters**: size, type, CR (XP and proficiency fill in), AC, HP, speed, abilities, saving throws,
  skills, resistances/immunities/vulnerabilities, condition immunities, automated traits (Pack
  Tactics, Parry, Magic Resistance, resistance or immunity to nonmagical weapons...), attacks with on-hit saving throws (extra damage, conditions),
  recharge attacks, multiattack, breath-style area abilities, and spellcasting with slots.
  **Place on map…** drops one on the board; they also appear (★) in the DM tab's creature list.
- **Spells**: level, school, casting time, range, concentration, class lists; targets (creatures,
  areas, self); spell attack, saving throw or no roll; damage with upcasting and cantrip scaling;
  healing; lasting effects (conditions, AC/speed changes, Bless/Bane-style dice, advantage or
  disadvantage, no reactions), repeat saves and pushes. They join class spell lists in the character
  creator, and **Teach spell** gives one straight to a creature.
- **Magic items**: weapons (+attack/+damage, extra damage dice), armor and shields (+AC), wondrous
  items (AC, saves, resistances, set an ability score, minimum speed) and potions (healing).
  The SRD basics are built in: +1/+2/+3 weapons, armor and shields, Flame Tongue, Frost Brand, Ring and
  Cloak of Protection, Bracers of Defense, Ring of Resistance, Gauntlets of Ogre Power and friends, and
  potions of healing. Hand items out from the DM tab to characters or monsters; they change the
  creature's numbers right away. On a monster, a magic weapon upgrades its matching attack (or adds
  a new one, with a thrown version for thrown weapons) and armor/shields add their bonus on top of the stat block's AC.
  Drinking a potion is an action button.

Homebrew saves with the campaign. **Export pack…/Import pack…** moves it between campaigns as a
`.json` file. Homebrew monster stat blocks stay hidden from players.

**Character sheet**: a dark-mode version of the official 5e sheet with the same three pages.
- **Character**: abilities, saves, skills, AC, HP, hit dice, death saves, attacks, equipment,
  personality, features.
- **Spells**: slots, plus spells by level; click a spell to cast it.
- **Details**: appearance, backstory, allies, treasure.

Numbers update live from the rules engine. The blank-on-paper fields (background, alignment, traits,
coins, backstory...) are editable by the DM and that character's player and are saved with the game.
Click an ability, save or skill to roll it. Rebind the key under *Project Settings → Input Map →
toggle_sheet*.

**Reactions**: when an opportunity attack, Shield, Uncanny Dodge, Deflect Missiles or Cutting Words
could help, the player gets a *Reaction!* prompt (30 seconds, then the sensible default is used;
the DM can answer for anyone). The game waits for the answer; nothing is applied until then. Each
creature's action bar has **Reactions: ask me / automatic / never**: players' characters ask by
default, the DM's creatures react automatically.

**On your turn** the bottom bar shows your Action ● Bonus ● Reaction ● and remaining movement.
- **⚔ attack buttons**: click, then click a target. Hovering a target shows advantage, disadvantage
  and cover before you commit.
- **✦ spell menus**: one per spell level. Creature spells: click targets (repeats allowed for rays and darts).
  Area spells: aim with the mouse, which previews who gets hit, then click.
- **★ features**: Second Wind, Action Surge, Rage, Flurry of Blows, Lay on Hands, Bardic Inspiration, and so on.
- The options row holds choices like *Bonus-action attack* (two-weapon fighting / martial arts /
  flurry / frenzy), *Reckless*, *Smite lv N*, *Stunning Strike*, *Slot level* and metamagic.
- In chat, `/r 2d6+3` rolls publicly and `/pr 1d20`
  rolls privately (only you and the DM see it).

**As the DM** (DM tab):
- Add creatures (pregens at any level, or monsters), then **Place…** and click the map.
- Paint walls, difficult terrain or floor by dragging on the map.
- Assign a creature to a player, change its side, toggle conditions, deal damage/heal, teleport,
  request saves/checks.
- Start/End combat, **Next Turn**, short/long rests for the party.
- *Monsters play themselves*: a simple AI that closes in and attacks. There's also an
  **Auto-play turn** button for one monster at a time.
- Optional rules: DMG 5-10-5 diagonals, flanking, monsters dying at 0 HP.
- Monster HP and AC are hidden from players; they see *Injured / Bloodied / Critical*.
- **Hidden tokens**: tick *Hidden* before **Place…** (or on a selected creature) to keep it off
  every player's screen. Hidden creatures sit out of initiative; untick to reveal them ("Goblin
  appears!") and they roll in. They can still move while hidden, but not attack or cast.
- **Fog of war**: tick *Fog of war for players*. Players only see what their party can see past
  walls (line of sight, shared by the whole party); squares they've seen before stay dimmed with no
  creatures shown. **Reset explored** makes them forget the map. The DM always sees everything.

## What the rules engine handles

**Turns:** initiative (Dex, ties broken by Dex score), surprise, rounds; one action, one bonus action,
one reaction (reset at the start of your turn), and movement split freely around actions.

**Movement:** 5 ft squares, PHB diagonals (or DMG 5-10-5), difficult terrain, standing up from prone
(half speed), crawling, moving through allies but not stopping there, hostile creatures blocking unless
two sizes apart, Large+ creature footprints, Dash, Disengage, opportunity attacks, dragging grappled
creatures, forced movement (pushes don't provoke).

**Attacks:** proficiency, finesse/ranged ability choice, reach, normal/long range, loading,
advantage/disadvantage from every condition and situation (prone in or out of 5 ft, unseen
attacker/target, ranged attacks with an enemy adjacent, Dodge, Help, Reckless, Pack Tactics, heavy
weapons for Small creatures...), natural 1/20, critical dice doubling, auto-crits on paralyzed or
unconscious targets within 5 ft, DMG grid cover (+2/+5/total), Extra Attack, Action Surge,
multiattack, two-weapon fighting, grapple/shove/escape.

**Damage:** resistance, vulnerability, immunity, temporary HP, concentration checks (DC 10 or half the
damage), massive damage, dying at 0 HP, death saves at the start of each turn (natural 20 regains 1 HP,
natural 1 counts double), damage while down, stabilizing, healing back to consciousness. Monsters die
at 0 HP by default.

**Conditions:** all 14 from the PHB plus exhaustion levels, with their mechanical effects, including
automatic Str/Dex save failures, speed 0, incapacitation ending concentration, and repeat saves at the
end of a turn.

**Spellcasting:** spell slots (full, half and pact casters), upcasting, cantrip scaling, concentration,
the bonus-action-spell rule, spell attacks, saves with half damage, areas (sphere, cube, cone, line)
with line of effect, Dex save cover bonus. 40 SRD spells: Fire Bolt, Eldritch Blast, Sacred Flame,
Vicious Mockery, Magic Missile, Shield (automatic reaction), Sleep, Bless, Bane, Hex, Hunter's Mark,
Cure Wounds, Healing Word, Guiding Bolt, Faerie Fire, Entangle, Thunderwave, Burning Hands, Scorching
Ray, Misty Step, Shatter, Hold Person, Aid, Lesser Restoration, Fireball, Lightning Bolt, Spirit
Guardians, Mass Healing Word, Revivify, Dispel Magic and more.

**Classes:** all twelve PHB classes with their SRD subclass, levels 1–20 for HP, proficiency, slots
and scaling numbers. Combat features through 5th level are automated:

| Class | Automated |
| --- | --- |
| Barbarian (Berserker) | Rage (and its end conditions), Unarmored Defense, Reckless Attack, Danger Sense, Frenzy, Extra Attack, Fast Movement |
| Bard (Lore) | Bardic Inspiration (auto-used when it would turn a failure into a success), Jack of All Trades, Cutting Words, Expertise |
| Cleric (Life) | Disciple of Life, Turn Undead, Destroy Undead, Preserve Life |
| Druid (Land) | Spellcasting, Shillelagh. *Wild Shape not yet.* |
| Fighter (Champion) | Fighting Styles, Second Wind, Action Surge, Improved Critical, Extra Attack |
| Monk (Open Hand) | Martial Arts, Ki (Flurry, Patient Defense, Step of the Wind), Unarmored Defense/Movement, Deflect Missiles, Open Hand Technique, Stunning Strike, Extra Attack |
| Paladin (Devotion) | Lay on Hands, Divine Smite, Fighting Style, Sacred Weapon, Extra Attack |
| Ranger (Hunter) | Fighting Style, Hunter's Mark, Colossus Slayer, Extra Attack |
| Rogue (Thief) | Sneak Attack (once per turn, on anyone's turn), Cunning Action, Uncanny Dodge, Expertise |
| Sorcerer (Draconic) | Draconic Resilience, Font of Magic, Quickened and Careful Spell |
| Warlock (Fiend) | Pact Magic, Dark One's Blessing, Agonizing Blast, Repelling Blast |
| Wizard (Evocation) | Arcane Recovery, Sculpt Spells |

**Races:** Human, Hill Dwarf, High Elf, Lightfoot Halfling, Dragonborn (breath weapon by ancestry),
Rock Gnome, Half-Elf, Half-Orc (Relentless Endurance, Savage Attacks), Tiefling, with their combat traits.

**Monsters:** Goblin (Nimble Escape), Kobold and Wolf (Pack Tactics, knockdown), Bandit, Skeleton,
Zombie (Undead Fortitude), Orc, Ghoul (paralyzing claws), Giant Spider (web, recharge, poison),
Bandit Captain (multiattack, Parry), Ogre, Owlbear, Red Dragon Wyrmling (fire breath).

### Simplifications and not-yet-done

- Divine Smite is declared before the attack roll, but the slot is only spent on a hit.
- Not yet implemented: the Ready action, Wild Shape, class features above 5th level, spells beyond the
  list above, lighting/darkvision and sight ranges (fog of war uses walls only), vertical movement and flying, Hiding beyond a Stealth vs passive
  Perception comparison. The DM can cover gaps with manual HP and condition controls.

## Adding content

Most of the time, use the Homebrew Workshop in-game. Built-in content is plain data in the same
format, so you can also add to it in code:

- Monsters: `scripts/data/monsters.gd` (stat-block fields, attacks with `to_hit`/`damage`, optional
  `on_hit` saves, `multiattack`, recharge powers).
- Spells: `scripts/data/spells.gd` (target type, attack or save, damage/healing, an effect template
  for conditions or buffs, durations in rounds).
- Magic items: `scripts/data/items.gd`.
- Characters: the creator (`scripts/ui/creator_panel.gd`) builds a definition (race, class, level,
  ability scores, skills, equipment, spells), `scripts/rules/creator.gd` checks it against the PHB
  rules, and `scripts/rules/builder.gd` turns it into a combatant. Pregens in `scripts/data/pregens.gd`
  use the same format.

## Code map

```
scripts/rules/      Rules engine (no UI code, fully testable)
  dice.gd           dice expressions, advantage, test hook for forced rolls
  grid.gd           distances, line of sight, DMG cover, pathfinding, area templates
  builder.gd        character/monster definitions -> combatants
  engine_base.gd    state queries, conditions, effects, saves & checks
  engine_combat.gd  attacks, damage, dying, movement, opportunity attacks, grapple/shove, actions
  engine_magic.gd   spellcasting, powers, class features
  rules_engine.gd   command dispatch, permissions, turn flow, rests, DM tools, monster AI
scripts/data/       SRD classes, races, equipment, spells, monsters, pregens
scripts/net/net.gd  host/join over ENet; the host runs the engine, clients send commands
scripts/ui/         3D board, tokens, camera, HUD, menu
tests/              headless rules tests
```

Every change to the game is a **command** (`{"type": "attack", "actor_id": ..., ...}`). The host
checks permissions, applies it with `RulesEngine.apply()` and sends each player their view of the
new state. Saves are the same state written to disk.

### Tests

```
godot --headless --path . --script res://tests/run_tests.gd     # rules engine tests
godot --path . -- --selftest                                    # drives the real UI through common flows
```

## Legal

This is a private, non-commercial project. Game rules content is based on the System Reference
Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC, available at
https://dnd.wizards.com/resources/systems-reference-document and licensed under the Creative Commons
Attribution 4.0 International License (https://creativecommons.org/licenses/by/4.0/legalcode).
