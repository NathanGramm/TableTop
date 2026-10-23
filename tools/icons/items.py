"""Item icons: assets/icons/items/<id>.png for every Equipment.WEAPONS / ARMOR id, "shield",
every Items.ALL id, ammunition, "focus", "unarmed" and the "wondrous" fallback for homebrew.

  python3 tools/icons/items.py path/to/game-icons/package/icons.json

See style.py for where icons.json comes from.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

import style

STEEL = ((240, 243, 247), (100, 108, 120))
IRON = ((205, 210, 218), (66, 72, 82))
WOOD = ((222, 168, 106), (92, 54, 24))
LEATHER = ((204, 146, 92), (86, 48, 22))
CLOTH = ((232, 216, 178), (120, 98, 66))
FUR = ((214, 186, 146), (104, 76, 48))
GOLD = ((255, 228, 132), (150, 98, 26))
FIRE = ((255, 240, 150), (214, 52, 8))
ICE = ((236, 252, 255), (70, 140, 214))
GEM = ((255, 255, 255), (130, 186, 232))
PEARL = ((255, 252, 246), (184, 168, 198))
RUNE = ((236, 244, 255), (96, 122, 170))

RARITY = {"uncommon": (60, 200, 90), "rare": (60, 130, 255), "very rare": (170, 80, 255), "legendary": (255, 150, 40)}

# id: (game-icons name or custom mask fn, material, scale, rarity glow / rgb glow, badge text)
WEAPONS = {
	"club": ("wood-club", WOOD), "dagger": ("plain-dagger", STEEL), "greatclub": ("spiked-bat", WOOD),
	"handaxe": ("wood-axe", STEEL), "javelin": ("spear-feather", STEEL), "light_hammer": ("flat-hammer", STEEL),
	"mace": ("flanged-mace", STEEL), "quarterstaff": ("_staff", WOOD), "sickle": ("sickle", STEEL),
	"spear": ("barbed-spear", STEEL), "light_crossbow": ("crossbow", WOOD, 0.72), "dart": ("dart", STEEL, 0.66),
	"shortbow": ("pocket-bow", WOOD), "sling": ("sling", LEATHER), "battleaxe": ("battle-axe", STEEL),
	"flail": ("flail", IRON), "glaive": ("glaive", STEEL), "greataxe": ("war-axe", STEEL), "greatsword": ("two-handed-sword", STEEL, 0.9),
	"halberd": ("halberd", STEEL), "lance": ("_lance", STEEL), "longsword": ("broadsword", STEEL), "maul": ("thor-hammer", IRON),
	"morningstar": ("spiked-mace", IRON), "pike": ("spear-hook", STEEL), "rapier": ("piercing-sword", STEEL),
	"scimitar": ("curvy-knife", STEEL), "shortsword": ("gladius", STEEL), "trident": ("trident", STEEL),
	"war_pick": ("war-pick", STEEL), "warhammer": ("warhammer", IRON), "whip": ("whip", LEATHER),
	"hand_crossbow": ("crossbow", WOOD, 0.56), "heavy_crossbow": ("crossbow", IRON, 0.86), "longbow": ("bow-string", WOOD, 0.86),
	"unarmed": ("fist", LEATHER),
}
ARMOR = {
	"padded": ("kevlar-vest", CLOTH), "leather": ("leather-armor", LEATHER), "studded_leather": ("leather-vest", LEATHER),
	"hide": ("fur-shirt", FUR), "chain_shirt": ("mail-shirt", STEEL), "scale_mail": ("scale-mail", STEEL),
	"breastplate": ("breastplate", STEEL), "half_plate": ("chest-armor", STEEL), "ring_mail": ("lamellar", IRON),
	"chain_mail": ("chain-mail", STEEL), "splint": ("abdominal-armor", IRON), "plate": ("shoulder-armor", STEEL),
	"shield": ("round-shield", WOOD),
}
OTHER = {
	"arrows": ("quiver", WOOD), "bolts": ("arrow-cluster", IRON), "bullets": ("stone-pile", IRON, 0.66),
	"focus": ("crystal-ball", GEM), "wondrous": ("fairy-wand", GOLD, 0.78, "uncommon"),
}
MAGIC = {
	"weapon_plus_1": ("rune-sword", RUNE, 0.78, "uncommon", "+1"), "weapon_plus_2": ("rune-sword", RUNE, 0.78, "rare", "+2"),
	"weapon_plus_3": ("rune-sword", RUNE, 0.78, "very rare", "+3"),
	"flame_tongue": ("broadsword", FIRE, 0.78, (255, 110, 20)), "frost_brand": ("broadsword", ICE, 0.78, (90, 200, 255)),
	"armor_plus_1": ("breastplate", RUNE, 0.78, "rare", "+1"), "armor_plus_2": ("breastplate", RUNE, 0.78, "very rare", "+2"),
	"armor_plus_3": ("breastplate", RUNE, 0.78, "legendary", "+3"),
	"shield_plus_1": ("magic-shield", RUNE, 0.78, "uncommon", "+1"), "shield_plus_2": ("magic-shield", RUNE, 0.78, "rare", "+2"),
	"shield_plus_3": ("magic-shield", RUNE, 0.78, "very rare", "+3"),
	"ring_of_protection": ("power-ring", GOLD, 0.74, "rare"), "cloak_of_protection": ("cloak", ((150, 170, 255), (40, 44, 120)), 0.78, "uncommon"),
	"bracers_of_defense": ("bracers", LEATHER, 0.78, "rare"), "ring_of_resistance": ("diamond-ring", GOLD, 0.74, "rare"),
	"gauntlets_of_ogre_power": ("gauntlet", IRON, 0.78, "uncommon"), "headband_of_intellect": ("tiara", GOLD, 0.78, "uncommon"),
	"amulet_of_health": ("gem-pendant", ((255, 150, 150), (150, 20, 30)), 0.78, "rare"),
	"belt_of_hill_giant_strength": ("belt", LEATHER, 0.8, "rare"), "boots_of_striding_and_springing": ("winged-leg", LEATHER, 0.78, "uncommon"),
	"potion_of_healing": ("health-potion", ((255, 130, 120), (150, 14, 24)), 0.74),
	"potion_of_greater_healing": ("round-potion", ((255, 110, 110), (130, 8, 30)), 0.74, "uncommon"),
	"potion_of_superior_healing": ("standing-potion", ((255, 96, 120), (110, 0, 40)), 0.74, "rare"),
	"potion_of_supreme_healing": ("magic-potion", ((255, 120, 200), (100, 0, 70)), 0.74, "very rare"),
	"diamond_300": ("diamonds", GEM, 0.6), "diamond_500": ("cut-diamond", GEM, 0.7),
	"diamond_dust_100": ("powder", GEM, 0.74), "pearl_100": ("oyster-pearl", PEARL, 0.74),
}


def _bar(points, width):
	m = Image.new("L", (style.S, style.S), 0)
	ImageDraw.Draw(m).line(points, fill=255, width=width, joint="curve")
	return m


def custom(name, scale):
	"""Weapons game-icons has no plain glyph for, drawn diagonally like the rest."""
	S = style.S
	if name == "_staff":
		m = _bar([(52, S - 52), (S - 52, 52)], 18)
		d = ImageDraw.Draw(m)
		for t in (0.12, 0.88):  # iron-shod ends
			x = 52 + t * (S - 104)
			d.ellipse((x - 14, S - x - 14, x + 14, S - x + 14), fill=255)
		return m
	# lance: a long cone with a round vamplate
	m = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(m)
	d.polygon([(222, 34), (84, 146), (110, 172)], fill=255)
	d.line([(40, 216), (96, 160)], fill=255, width=20)
	d.ellipse((66, 128, 128, 190), fill=255)
	return m


def make(spec):
	name, mat = spec[0], spec[1]
	scale = spec[2] if len(spec) > 2 else 0.78
	glow = spec[3] if len(spec) > 3 else None
	badge = spec[4] if len(spec) > 4 else None
	mask = custom(name, scale) if name.startswith("_") else style.glyph_mask(name, scale)
	img = style.tile([(mask, mat)], glow=RARITY.get(glow, glow))
	if badge:
		d = ImageDraw.Draw(img)
		font = ImageFont.truetype("DejaVuSans-Bold.ttf", 58)
		d.text((S_BADGE, S_BADGE), badge, font=font, anchor="mm", fill=(255, 226, 130), stroke_width=7, stroke_fill=(20, 14, 8))
	return img


S_BADGE = 190


def main():
	style.load(sys.argv[1])
	out = os.path.join(os.path.dirname(__file__), "../../assets/icons/items")
	os.makedirs(out, exist_ok=True)
	for table in (WEAPONS, ARMOR, OTHER, MAGIC):
		for id, spec in table.items():
			style.save(make(spec), os.path.join(out, id + ".png"))
	print(sum(map(len, (WEAPONS, ARMOR, OTHER, MAGIC))), "icons ->", os.path.normpath(out))


if __name__ == "__main__":
	main()
