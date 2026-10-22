class_name TipButton
extends Button
## A button whose tooltip is a BBCode card (name, stats, description).


func _make_custom_tooltip(for_text: String) -> Object:
	return UiKit.tip_card(for_text)
