extends RefCounted
class_name ActionWheel
## The left thumb's ACTION WHEEL — the fight's only action control (Jan, Nov 2026).
##
## Jan: "Kouzla a lektvary zabírají příliš mnoho místa a hlavně hráč se musí neustále koukat kam
## kliká … něco jako levý joystick, kdy podle toho kterým směrem hráč táhne, podle toho se použije
## kouzlo/lektvar/útok. Může tam zůstat ta kruhová oblast jak u pohybu a když hráč určitým směrem
## přetáhne mimo kruh, tak se to bere jako aktivace. … hráč musí mít možnost nabindovat akce na
## libovolná tlačítka (směry)."
##
## So there are no fixed buttons any more: the wheel appears wherever the thumb lands, six sectors
## 60° apart, and the direction the thumb is pushed into IS the action. The thumb never has to
## find a 44 px circle, and the icons sit on the ring — outside the thumb's own disc.
##
## Six rather than eight: at the ring's 58 px, six sectors put 61 px between two icon centres,
## which is what lets a 20 px icon read as a symbol on a phone. Eight would leave 5 px of daylight
## between them and the wheel would be a smear.
##
## The sector centres are UP, UP-RIGHT, DOWN-RIGHT, DOWN, DOWN-LEFT, UP-LEFT. No sector sits on
## the pure horizontal, which is where a thumb resting flat actually points — with one there, a
## relaxed thumb would hold an action the player never meant.

const SLOTS := 6

const ATTACK := "attack"
const POTION := "potion"
const EMPTY := ""

## The default layout: the two things every fight needs first, then the class's spells in bar
## order. Only a DEFAULT — the player's own bindings win, and they are what gets saved.
static func default_slots(bar: Array) -> Array:
	var out: Array = [ATTACK, POTION]
	for e in bar:
		if out.size() >= SLOTS:
			break
		out.append(str((e as Dictionary).get("id", "")))
	while out.size() < SLOTS:
		out.append(EMPTY)
	return out


## A save can hold anything (a short array, a number, nothing at all), so every read goes through
## here: exactly SLOTS strings, padded with EMPTY.
static func normalize(slots: Variant) -> Array:
	var out: Array = []
	if slots is Array:
		for s in slots:
			if out.size() >= SLOTS:
				break
			out.append(str(s))
	while out.size() < SLOTS:
		out.append(EMPTY)
	return out


## The centre of sector `i`, in radians. Sector 0 is UP (-90°) and they run clockwise.
static func centre_angle(i: int) -> float:
	return -PI * 0.5 + TAU * float(i) / float(SLOTS)


## Which sector a thumb offset points into, or -1 for "not far enough to mean anything".
## The offset is measured from where the thumb landed, so this is a joystick direction, not a
## position on the screen.
static func sector_at(offset: Vector2) -> int:
	if offset.length() < 0.001:
		return -1
	return posmod(int(round((offset.angle() + PI * 0.5) / (TAU / float(SLOTS)))), SLOTS)


## Hold or trigger? A held sector keeps playing its action for as long as the thumb stays
## (`attack`, an offensive spell — the run's own repeat rule paces it). Everything else FIRES once,
## on entering the sector: a potion drunk twice because the thumb drifted would be a bug the
## player pays for, and a queued spell or a shout has nothing to hold.
static func is_hold(action: String, spells) -> bool:
	if action == ATTACK:
		return true
	return spells.is_offensive(action)


## The one place the wheel knows what an action is called. Icons and the bind panel both read it,
## so a renamed spell cannot show two different names in one frame.
static func action_name(action: String, bar: Array) -> String:
	if action == EMPTY:
		return "—"
	if action == ATTACK:
		return "Útok"
	if action == POTION:
		return "Lektvar"
	for e in bar:
		if str((e as Dictionary).get("id", "")) == action:
			return str((e as Dictionary).get("name", action))
	return action
