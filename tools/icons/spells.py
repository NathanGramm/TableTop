"""Renders a 64x64 icon for every spell in scripts/data/spells.gd into assets/icons/spells/<id>.png,
plus school_<school>.png fallbacks for homebrew spells.

Glyphs are game-icons.net silhouettes (CC BY 3.0), read from the @iconify-json/game-icons package:
    npm pack @iconify-json/game-icons && tar xzf iconify-json-game-icons-*.tgz
    pip install cairosvg pillow
    python3 tools/icons/spells.py package/icons.json

Tiles are drawn by tools/icons/style.py, shared with items. Spells tint the tile by school and the glyph by
what the spell does.
"""
import re
import sys
from pathlib import Path

import style

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/icons/spells"

SCHOOL = {  # tile tint
	"abjuration": (58, 110, 176), "conjuration": (176, 122, 42), "divination": (70, 150, 160),
	"enchantment": (176, 70, 138), "evocation": (176, 58, 42), "illusion": (118, 72, 176),
	"necromancy": (60, 120, 72), "transmutation": (138, 138, 48),
}
SCHOOL_GLYPH = {  # fallback glyph per school
	"abjuration": "magic-shield", "conjuration": "magic-portal", "divination": "crystal-eye",
	"enchantment": "charm", "evocation": "fire-spell-cast", "illusion": "invisible",
	"necromancy": "death-skull", "transmutation": "magic-swirl",
}
TINT = {  # glyph gradient (top, bottom)
	"fire": ((255, 214, 110), (230, 90, 30)), "cold": ((225, 248, 255), (110, 180, 235)),
	"lightning": ((255, 250, 170), (240, 190, 40)), "necrotic": ((200, 230, 170), (90, 120, 70)),
	"radiant": ((255, 246, 200), (240, 190, 70)), "psychic": ((255, 200, 240), (210, 90, 190)),
	"force": ((225, 205, 255), (150, 110, 240)), "poison": ((210, 255, 140), (100, 180, 50)),
	"thunder": ((220, 230, 255), (120, 140, 210)), "heal": ((215, 255, 210), (90, 200, 110)),
	"holy": ((255, 250, 225), (230, 200, 120)), "nature": ((200, 240, 150), (90, 150, 60)),
	"dark": ((170, 160, 200), (70, 60, 110)), "stone": ((225, 220, 205), (140, 130, 115)),
	"arcane": ((240, 240, 250), (175, 180, 205)), "blood": ((255, 160, 150), (190, 40, 40)),
}
# spell id: (game-icons name, tint)
GLYPH = {
	"fire_bolt": ("fire-ray", "fire"), "ray_of_frost": ("ice-bolt", "cold"),
	"shocking_grasp": ("lightning-helix", "lightning"), "chill_touch": ("evil-hand", "necrotic"),
	"poison_spray": ("poison-gas", "poison"), "sacred_flame": ("candle-flame", "radiant"),
	"vicious_mockery": ("imp-laugh", "psychic"), "eldritch_blast": ("plasma-bolt", "force"),
	"produce_flame": ("fire-spell-cast", "fire"), "shillelagh": ("wizard-staff", "nature"),
	"magic_missile": ("missile-swarm", "force"), "burning_hands": ("fire-breath", "fire"),
	"thunderwave": ("sound-waves", "thunder"), "shield": ("magic-shield", "force"),
	"hellish_rebuke": ("burning-skull", "fire"), "alarm": ("ringing-bell", "arcane"),
	"comprehend_languages": ("open-book", "arcane"), "detect_magic": ("crystal-eye", "arcane"),
	"detect_poison_and_disease": ("poison-bottle", "poison"), "identify": ("magnifying-glass", "arcane"),
	"purify_food_and_drink": ("chalice-drops", "holy"), "speak_with_animals": ("paw", "nature"),
	"unseen_servant": ("floating-ghost", "arcane"), "thaumaturgy": ("sparkles", "radiant"),
	"sleep": ("night-sleep", "psychic"), "cure_wounds": ("healing", "heal"),
	"healing_word": ("heart-wings", "heal"), "guiding_bolt": ("sunbeams", "radiant"),
	"bless": ("holy-symbol", "holy"), "bane": ("cursed-star", "dark"),
	"inflict_wounds": ("death-skull", "necrotic"), "hunters_mark": ("targeting", "blood"),
	"hex": ("evil-eyes", "dark"), "shield_of_faith": ("cross-shield", "holy"),
	"faerie_fire": ("fairy-wings", "psychic"), "entangle": ("curling-vines", "nature"),
	"dissonant_whispers": ("psychic-waves", "psychic"), "mage_armor": ("layered-armor", "force"),
	"false_life": ("heart-drop", "necrotic"), "longstrider": ("boot-prints", "nature"),
	"ray_of_sickness": ("bubbling-beam", "poison"), "tashas_hideous_laughter": ("happy-skull", "psychic"),
	"scorching_ray": ("fire-dash", "fire"), "darkness": ("evil-moon", "dark"),
	"silence": ("silenced", "arcane"), "misty_step": ("dust-cloud", "arcane"),
	"shatter": ("shatter", "thunder"), "hold_person": ("handcuffed", "psychic"),
	"aid": ("health-increase", "holy"), "lesser_restoration": ("health-potion", "heal"),
	"spiritual_weapon": ("spinning-sword", "radiant"), "blur": ("invisible", "arcane"),
	"web": ("spider-web", "arcane"), "blindness_deafness": ("dead-eye", "necrotic"),
	"prayer_of_healing": ("prayer", "heal"), "fireball": ("fireball", "fire"),
	"lightning_bolt": ("lightning-arc", "lightning"), "mass_healing_word": ("heart-plus", "heal"),
	"spirit_guardians": ("angel-wings", "radiant"), "revivify": ("heart-beats", "heal"),
	"dispel_magic": ("magic-swirl", "arcane"), "fear": ("terror", "dark"),
	"hypnotic_pattern": ("spiral-bloom", "psychic"), "fly": ("feathered-wing", "arcane"),
	"haste": ("running-ninja", "lightning"), "conjure_barrage": ("arrow-cluster", "stone"),
	"counterspell": ("magic-palm", "force"), "slow": ("snail", "cold"),
	"ice_storm": ("snowing", "cold"), "blight": ("leaf-skeleton", "necrotic"),
	"greater_invisibility": ("invisible-face", "arcane"), "dimension_door": ("magic-portal", "force"),
	"death_ward": ("ankh", "holy"), "stoneskin": ("stone-block", "stone"),
	"cone_of_cold": ("frostfire", "cold"), "flame_strike": ("fire-zone", "fire"),
	"mass_cure_wounds": ("heart-tower", "heal"), "hold_monster": ("crossed-chains", "stone"),
	"raise_dead": ("raise-zombie", "holy"), "greater_restoration": ("sun", "holy"),
}


def tile(school, name, tint):
	col = SCHOOL[school]
	bg = (tuple(round(c * 0.62) for c in col), tuple(round(c * 0.16) for c in col))
	return style.tile([(style.glyph_mask(name, 0.70), TINT[tint])], bg=bg)


def main(icons_json):
	style.load(icons_json)
	src = (ROOT / "scripts/data/spells.gd").read_text()
	spells = re.findall(r'^\s*"([a-z0-9_]+)": \{"name": "[^"]+", "level": \d, "school": "([a-z]+)"', src, re.M)
	OUT.mkdir(parents=True, exist_ok=True)
	missing = [sid for sid, _ in spells if sid not in GLYPH]
	assert not missing, "no glyph chosen for %s" % missing
	for sid, school in spells:
		name, tint = GLYPH[sid]
		style.save(tile(school, name, tint), OUT / (sid + ".png"))
	for school, name in SCHOOL_GLYPH.items():
		style.save(tile(school, name, "arcane"), OUT / ("school_%s.png" % school))
	print("%d spell icons + %d school fallbacks -> %s" % (len(spells), len(SCHOOL), OUT))


if __name__ == "__main__":
	main(sys.argv[1])
