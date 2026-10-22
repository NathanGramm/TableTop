class_name TipRichText
extends RichTextLabel
## A rich label whose tooltip is a BBCode card, for the sheet's clickable spells, saves and skills.


func _make_custom_tooltip(for_text: String) -> Object:
	return UiKit.tip_card(for_text)
