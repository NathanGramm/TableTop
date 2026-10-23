"""Renders assets/icons/actions/<id>.png: 64x64 icons for standard actions, class features, feats and
monster actions, keyed by the game's ids.

Glyphs are game-icons.net silhouettes (CC BY 3.0, see assets/icons/CREDITS.md), read from the npm
package @iconify-json/game-icons:
    npm pack @iconify-json/game-icons && tar xzf iconify-json-game-icons-*.tgz
    pip install cairosvg pillow
    python3 tools/icons/actions.py package/icons.json
The tile (frame, background, outline, highlight, shadow) follows the shared style of tools/icons/items.py;
the background is tinted by what the icon costs: action, bonus action, reaction, free/movement, passive.
"""
import io
import json
import os
import sys

import cairosvg
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icons", "actions")
BIG, SIZE = 256, 64

# Background centre/edge colours per action economy.
TINT = {
    "action": ((122, 34, 30), (30, 12, 10)),
    "bonus": ((128, 96, 26), (32, 24, 8)),
    "reaction": ((86, 46, 128), (22, 12, 34)),
    "free": ((26, 104, 104), (8, 26, 28)),
    "passive": ((58, 66, 80), (16, 18, 22)),
}

# id -> (game-icons glyph, economy)
ICONS = {
    # Standard actions and generic attacks
    "attack_melee": ("crossed-swords", "action"),
    "attack_ranged": ("bow-arrow", "action"),
    "unarmed": ("punch", "action"),
    "dash": ("sprint", "action"),
    "disengage": ("exit-door", "action"),
    "dodge": ("dodge", "action"),
    "hide": ("hidden", "action"),
    "ready": ("hourglass", "action"),
    "help": ("shaking-hands", "action"),
    "grapple": ("grab", "action"),
    "shove_prone": ("push", "action"),
    "shove_push": ("shield-bash", "action"),
    "escape": ("breaking-chain", "action"),
    "stabilize": ("bandage-roll", "action"),
    "wake": ("alarm-clock", "action"),
    "search": ("magnifying-glass", "action"),
    "use_object": ("hand", "action"),
    "door": ("wooden-door", "free"),
    "jump": ("jump-across", "free"),
    "fly_up": ("feathered-wing", "free"),
    "fly_down": ("falling", "free"),
    "land": ("footprint", "free"),
    "standUp": ("body-height", "free"),
    "hands": ("hand-grip", "free"),
    "end_turn": ("stop-sign", "free"),
    "auto_turn": ("cog", "free"),
    "light": ("torch", "free"),
    "opportunity_attack": ("sword-clash", "reaction"),
    "reactions": ("lightning-helix", "reaction"),
    # Class features
    "rage": ("enrage", "bonus"),
    "endRage": ("peace-dove", "bonus"),
    "frenzy": ("axe-swing", "bonus"),
    "recklessAttack": ("angry-eyes", "free"),
    "unarmoredDefense": ("muscular-torso", "passive"),
    "dangerSense": ("ninja-heroic-stance", "passive"),
    "mindlessRage": ("brain-freeze", "passive"),
    "feralInstinct": ("beast-eye", "passive"),
    "relentlessRage": ("heart-beats", "passive"),
    "persistentRage": ("flame", "passive"),
    "bardicInspiration": ("lyre", "bonus"),
    "cuttingWords": ("shouting", "reaction"),
    "superiorInspiration": ("music-spell", "passive"),
    "fontOfMagic": ("magic-swirl", "bonus"),
    "createSlot": ("crystal-growth", "bonus"),
    "convertSlot": ("crystal-shine", "bonus"),
    "sorcerousRestoration": ("crystal-ball", "passive"),
    "secondWind": ("healing", "bonus"),
    "actionSurge": ("extra-time", "free"),
    "indomitable": ("stone-tower", "free"),
    "remarkableAthlete": ("weight-lifting-up", "passive"),
    "survivor": ("heart-plus", "passive"),
    "sneakAttack": ("backstab", "passive"),
    "cunningAction": ("cloak-dagger", "bonus"),
    "fastHands": ("robber-hand", "bonus"),
    "uncannyDodge": ("shield-reflect", "reaction"),
    "evasion": ("dodging", "passive"),
    "elusive": ("ghost", "passive"),
    "supremeSneak": ("hood", "passive"),
    "martialArts": ("high-kick", "bonus"),
    "flurryOfBlows": ("punch-blast", "bonus"),
    "patientDefense": ("meditation", "bonus"),
    "stepOfTheWind": ("whirlwind", "bonus"),
    "deflectMissiles": ("arrows-shield", "reaction"),
    "slowFall": ("feather", "reaction"),
    "stunningStrike": ("fulguro-punch", "free"),
    "openHand": ("open-palm", "free"),
    "perfectSelf": ("yin-yang", "passive"),
    "waterWalk": ("water-drop", "passive"),
    "stillness_of_mind": ("lotus", "action"),
    "wholeness_of_body": ("glowing-hands", "action"),
    "divineSmite": ("sun-spear", "free"),
    "improvedSmite": ("barbed-sun", "passive"),
    "layOnHands": ("healing-shield", "action"),
    "divine_sense": ("all-seeing-eye", "action"),
    "sacredWeapon": ("winged-sword", "action"),
    "auraOfProtection": ("aura", "passive"),
    "auraOfCourage": ("lion", "passive"),
    "auraOfDevotion": ("holy-symbol", "passive"),
    "turnUndead": ("skull-crossed-bones", "action"),
    "discipleOfLife": ("heart-bottle", "passive"),
    "blessedHealer": ("hand-of-god", "passive"),
    "preserveLife": ("life-support", "action"),
    "preserve_life": ("life-support", "action"),
    "supremeHealing": ("health-increase", "passive"),
    "divine_intervention": ("angel-wings", "action"),
    "spiritualWeapon": ("sparkling-sabre", "bonus"),
    "wildShape": ("wolf-howl", "action"),
    "revertShape": ("person", "bonus"),
    "naturalRecovery": ("oak-leaf", "passive"),
    "landsStride": ("vine-leaf", "passive"),
    "beastSpells": ("bear-head", "passive"),
    "archdruid": ("tree-face", "passive"),
    "favoredEnemy": ("target-dummy", "passive"),
    "colossusSlayer": ("giant", "passive"),
    "vanish": ("invisible", "bonus"),
    "foeSlayer": ("on-target", "passive"),
    "darkOnesBlessing": ("burning-skull", "passive"),
    "darkOnesOwnLuck": ("dice-twenty-faces-twenty", "free"),
    "potentCantrip": ("spark-spirit", "passive"),
    "empoweredEvocation": ("fire-ring", "passive"),
    "sculptSpells": ("magic-shield", "passive"),
    "countercharm": ("music-spell", "action"),
    "intimidating_presence": ("screaming", "action"),
    "breath_weapon": ("dragon-breath", "action"),
    "infernal_darkness": ("evil-moon", "action"),
    # Feats
    "actor": ("duality-mask", "passive"),
    "alert": ("eye-target", "passive"),
    "athlete": ("run", "passive"),
    "charger": ("charging-bull", "passive"),
    "crossbowExpert": ("crossbow", "passive"),
    "defensiveDuelist": ("crossed-sabres", "reaction"),
    "dualWielder": ("dervish-swords", "passive"),
    "dungeonDelver": ("dungeon-gate", "passive"),
    "durable": ("heart-armor", "passive"),
    "elementalAdept": ("fire-spell-cast", "passive"),
    "grappler": ("grapple", "passive"),
    "pin": ("handcuffs", "action"),
    "greatWeaponMaster": ("battle-axe", "passive"),
    "healer": ("medical-pack", "passive"),
    "healerKit": ("medical-pack", "action"),
    "heavilyArmored": ("breastplate", "passive"),
    "heavyArmorMaster": ("armor-upgrade", "passive"),
    "inspiringLeader": ("public-speaker", "action"),
    "keenMind": ("brain", "passive"),
    "lightlyArmored": ("leather-vest", "passive"),
    "linguist": ("scroll-quill", "passive"),
    "lucky": ("clover", "free"),
    "mageSlayer": ("magic-axe", "reaction"),
    "magicInitiate": ("spell-book", "passive"),
    "martialAdept": ("sword-spin", "passive"),
    "mediumArmorMaster": ("chain-mail", "passive"),
    "mobile": ("wingfoot", "passive"),
    "moderatelyArmored": ("chest-armor", "passive"),
    "mountedCombatant": ("mounted-knight", "passive"),
    "observant": ("magnifying-glass", "passive"),
    "polearmMaster": ("halberd", "bonus"),
    "resilient": ("shield-echoes", "passive"),
    "ritualCaster": ("candle-holder", "passive"),
    "savageAttacker": ("bloody-sword", "passive"),
    "sentinel": ("guarded-tower", "reaction"),
    "sharpshooter": ("archery-target", "passive"),
    "shieldMaster": ("round-shield", "bonus"),
    "skilled": ("skills", "passive"),
    "skulker": ("hooded-figure", "passive"),
    "spellSniper": ("crosshair-arrow", "passive"),
    "tavernBrawler": ("beer-stein", "passive"),
    "tough": ("muscle-up", "passive"),
    "warCaster": ("bolt-spell-cast", "reaction"),
    "weaponMaster": ("swords-emblem", "passive"),
    # Monster attacks, powers, legendary actions and traits
    "bite": ("fangs", "action"),
    "claw": ("claw-slashes", "action"),
    "claws": ("triple-claws", "action"),
    "beak": ("eagle-head", "action"),
    "talons": ("grasping-claws", "action"),
    "tail": ("spiked-tail", "action"),
    "horn": ("rhinoceros-horn", "action"),
    "hooves": ("hoof", "action"),
    "tusk": ("boar-tusks", "action"),
    "slam": ("fist", "action"),
    "fist": ("mailed-fist", "action"),
    "rock": ("falling-boulder", "action"),
    "web": ("spider-web", "action"),
    "life_drain": ("vampire-dracula", "action"),
    "fire_breath": ("fire-breath", "action"),
    "cold_breath": ("ice-spell-cast", "action"),
    "poison_breath": ("poison-gas", "action"),
    "wing_attack": ("bat-wing", "action"),
    "healing_touch": ("glowing-hands", "action"),
    "heal_self": ("health-increase", "action"),
    "shimmering_shield": ("energy-shield", "action"),
    "legendary": ("crowned-skull", "free"),
    "multiattack": ("spinning-blades", "action"),
    "aggressive": ("charging-bull", "bonus"),
    "brave": ("lion", "passive"),
    "feyAncestry": ("fairy-wings", "passive"),
    "magicResistance": ("magic-shield", "passive"),
    "nimbleEscape": ("running-ninja", "bonus"),
    "nonmagicalResistance": ("shield", "passive"),
    "packTactics": ("wolf-head", "passive"),
    "parry": ("crossed-sabres", "reaction"),
    "undeadFortitude": ("half-dead", "passive"),
}


def glyph_mask(body: str, size: int) -> Image.Image:
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">%s</svg>' % body.replace("currentColor", "#fff")
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")


def radial(size: int, inner, outer, centre=(0.5, 0.42)) -> Image.Image:
    # Radial gradient by resizing a 1-D ramp around the centre.
    g = Image.new("L", (size, size))
    px = g.load()
    cx, cy = centre[0] * size, centre[1] * size
    r = size * 0.75
    for y in range(size):
        for x in range(size):
            px[x, y] = min(255, int(255 * (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / r))
    return Image.composite(Image.new("RGB", (size, size), outer), Image.new("RGB", (size, size), inner), g)


def vertical(size: int, top, bottom) -> Image.Image:
    g = Image.linear_gradient("L").resize((size, size))
    return Image.composite(Image.new("RGB", (size, size), bottom), Image.new("RGB", (size, size), top), g)


_BG = {}


def tile(mask: Image.Image, economy: str) -> Image.Image:
    if economy not in _BG:
        _BG[economy] = radial(BIG, *TINT[economy])
    radius, frame = 40, 8
    shape = Image.new("L", (BIG, BIG))
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, BIG - 1, BIG - 1), radius, fill=255)
    img = Image.new("RGBA", (BIG, BIG))
    img.paste(_BG[economy], (0, 0), shape)
    # Glyph centred at ~70%, with drop shadow, near-black outline, gradient fill and a top-left highlight.
    g = Image.new("L", (BIG, BIG))
    off = (BIG - mask.width) // 2
    g.paste(mask, (off, off))
    outline = g.filter(ImageFilter.MaxFilter(9))
    shadow = outline.filter(ImageFilter.GaussianBlur(6)).point(lambda v: v * 0.7)
    img.paste((0, 0, 0), (6, 8), Image.composite(shadow, Image.new("L", (BIG, BIG)), shape).crop((0, 0, BIG - 6, BIG - 8)))
    img.paste((14, 10, 8), (0, 0), outline)
    img.paste(vertical(BIG, (250, 238, 210), (184, 150, 98)), (0, 0), g)
    hl = radial(BIG, (255, 255, 255), (0, 0, 0), (0.3, 0.25)).convert("L").point(lambda v: max(0, v - 150))
    img.paste((255, 255, 255), (0, 0), ImageChops.multiply(g, hl))
    # Bronze frame: outer line then a darker inner line.
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, BIG - 1, BIG - 1), radius, outline=(138, 106, 58), width=frame)
    d.rounded_rectangle((frame, frame, BIG - 1 - frame, BIG - 1 - frame), radius - frame, outline=(64, 46, 22), width=3)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), shape))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main(icons_json: str) -> None:
    glyphs = json.load(open(icons_json))["icons"]
    missing = sorted({g for g, _ in ICONS.values() if g not in glyphs})
    assert not missing, "unknown glyphs: %s" % missing
    os.makedirs(OUT, exist_ok=True)
    for id_, (glyph, economy) in ICONS.items():
        tile(glyph_mask(glyphs[glyph]["body"], int(BIG * 0.7)), economy).save(os.path.join(OUT, id_ + ".png"), optimize=True)
    print("%d icons -> %s" % (len(ICONS), os.path.normpath(OUT)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "package/icons.json")
