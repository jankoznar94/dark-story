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
## So there are no fixed buttons any more: six sectors 60° apart, and the direction the thumb is
## pushed into IS the action. Jan's second pass made the wheel PERMANENT (it is drawn all the time,
## bottom-left) and turned each slot into a full WEDGE of an outer ring, so the thumb only has to
## land in the wedge, never on a small icon.
##
## Six rather than eight: six sectors of one ring leave the icons 61 px apart, which is what lets a
## 20 px symbol read as a symbol on a phone. Eight would put them 5 px apart and the wheel would be
## a smear.
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


## Hold or release? Jan, second pass: "Útok jako jediný bude takový, že stačí najet na výseč a
## držet a útok se hned aktivuje a je aktivní dokud tam hráč drží prst. U kouzel a potionů … až
## puštění kontaktu bude považováno za aktivaci."
##
## So the ATTACK is the ONLY hold action. Everything else — the potion AND every spell, offensive
## ones included — is armed by dragging into its wedge and fires when the thumb LIFTS. That is what
## stops a spell from firing on a drifted thumb and stops one gesture from firing twice.
static func is_hold(action: String, _spells = null) -> bool:
	return action == ATTACK


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
