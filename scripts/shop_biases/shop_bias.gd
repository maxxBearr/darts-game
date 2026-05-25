class_name ShopBias
extends Resource
## Base class for passive shop-shaping abilities attached to dart components.
## Subclass this and override get_weight_overrides() to bias the modifier pool.


## Override to return a {Script: float_multiplier} dictionary that the
## ModifierRegistry multiplies into pool weights at shop generation time.
func get_weight_overrides() -> Dictionary:
	return {}
