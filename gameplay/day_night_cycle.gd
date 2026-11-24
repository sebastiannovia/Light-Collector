extends CanvasModulate
class_name DayNightCycle

signal night_changed(is_night: bool)
signal clock_changed(hour: float, is_night: bool, day_number: int, permanent_night: bool)

const DAY_SECONDS: Array[float] = [60.0, 55.0, 45.0, 40.0, 30.0]
const NIGHT_SECONDS: Array[float] = [180.0, 185.0, 195.0, 200.0, 210.0]
const NIGHT_START := 20.0
const NIGHT_END := 5.0
const HOURS_PER_CYCLE := 24.0
const NIGHT_COLOR := Color(0.27, 0.36, 0.59)
const DAWN_COLOR := Color(0.89, 0.66, 0.57)
const DAY_COLOR := Color(1.0, 1.0, 0.97)
const DUSK_COLOR := Color(1.0, 0.71, 0.50)

var hour := NIGHT_END
var is_night := false
var day_number := 1
var permanent_night: bool:
	get:
		return day_number > DAY_SECONDS.size()

var _phase_elapsed := 0.0
var _display_minute := -1
var _display_day := 0


func _enter_tree() -> void:
	add_to_group("day_night_cycle")


func _ready() -> void:
	_update_view()


func _process(delta: float) -> void:
	_advance_time(delta)


func _advance_time(seconds: float) -> void:
	if permanent_night:
		return
	var remaining := maxf(seconds, 0.0)
	while remaining > 0.0 and not permanent_night:
		var time_left := _phase_duration() - _phase_elapsed
		if remaining < time_left:
			_phase_elapsed += remaining
			break
		remaining -= time_left
		_phase_elapsed = 0.0
		if is_night:
			day_number += 1
			if permanent_night:
				break
		is_night = not is_night
		_update_view()
		night_changed.emit(is_night)
	_update_view()


func _phase_duration() -> float:
	var durations := NIGHT_SECONDS if is_night else DAY_SECONDS
	return durations[day_number - 1]


func _update_view() -> void:
	if permanent_night:
		hour = NIGHT_START
	elif is_night:
		var progress := _phase_elapsed / _phase_duration()
		hour = fposmod(lerpf(NIGHT_START, NIGHT_END + HOURS_PER_CYCLE, progress), HOURS_PER_CYCLE)
	else:
		hour = lerpf(NIGHT_END, NIGHT_START, _phase_elapsed / _phase_duration())
	color = _ambient_color()
	var minute := floori(hour * 60.0)
	if minute != _display_minute or day_number != _display_day:
		_display_minute = minute
		_display_day = day_number
		clock_changed.emit(hour, is_night, day_number, permanent_night)


func _ambient_color() -> Color:
	if hour < NIGHT_END or hour >= NIGHT_START:
		return NIGHT_COLOR
	if hour < 6.25:
		return NIGHT_COLOR.lerp(DAWN_COLOR, smoothstep(NIGHT_END, 6.25, hour))
	if hour < 8.0:
		return DAWN_COLOR.lerp(DAY_COLOR, smoothstep(6.25, 8.0, hour))
	if hour < 17.0:
		return DAY_COLOR
	if hour < 18.5:
		return DAY_COLOR.lerp(DUSK_COLOR, smoothstep(17.0, 18.5, hour))
	return DUSK_COLOR.lerp(NIGHT_COLOR, smoothstep(18.5, NIGHT_START, hour))
