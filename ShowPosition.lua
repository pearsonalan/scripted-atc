DataRef("heading_bug", "sim/cockpit/autopilot/heading", "readonly" )
DataRef("latitude", "sim/flightmodel/position/latitude", "readonly" )
DataRef("longitude", "sim/flightmodel/position/longitude", "readonly" )
DataRef("altitude", "sim/flightmodel/position/elevation", "readonly" )
DataRef("selected_com_out", "sim/cockpit/switches/audio_panel_out", "readonly")
DataRef("com1_freq_hz", "sim/cockpit/radios/com1_freq_hz", "readonly")
DataRef("com2_freq_hz", "sim/cockpit/radios/com2_freq_hz", "readonly")

function meters_to_feet(meters)
	return meters * 3.28084
end

function draw_position()
	local posx = SCREEN_WIDTH - 200
	local posy = SCREEN_HIGHT - 20          -- SIC
	local line_height = 20

	draw_string_Helvetica_18(posx, posy,
							 "HDG: " .. math.floor(heading_bug + 0.5))
	draw_string_Helvetica_18(posx, posy - line_height,
							 "LAT: " .. string.format("%0.4f", latitude))
	draw_string_Helvetica_18(posx, posy - 2 * line_height,
							 "LON: " .. string.format("%0.4f", longitude))
	draw_string_Helvetica_18(posx, posy - 3 * line_height,
							 "ALT: " .. string.format("%d", meters_to_feet(altitude)))
end

do_every_draw("draw_position()")

local atc_debug_string = "ATC Result"
local key_press_time = os.clock()

function show_atc_result()
    glColor4f(255, 255, 255, 255)
	draw_string_Helvetica_18(50, SCREEN_HIGHT-130, atc_debug_string)
end

do_every_draw("show_atc_result()")

function reset_atc_result()
	if os.clock() - key_press_time > 1.0 then
		atc_debug_string = ""
	end
end

do_often("reset_atc_result()")

function keystroke_handler()
	if VKEY == 13 then
		atc_debug_string = "Return pressed"
		key_press_time = os.clock()
		RESUME_KEY = true
	end
end

do_on_keystroke("keystroke_handler()")

function cc_end() 
	local frequency = nil
	local com = nil
	if selected_com_out == 6 then
		com = "COM1"
		frequency = com1_freq_hz
	elseif selected_com_out == 7 then
		com = "COM2"
		frequency = com2_freq_hz
	end
	if frequency ~= nil then
		local msg = string.format("%s frequency is %d", com, frequency)
		print(msg)
		atc_debug_string = msg
		key_press_time = os.clock()
	end
end

create_command("FlyWithLua/ShowPosition/TestCommand", "ShowPosition Test Cmd",
			   "", "", "cc_end()")

-- function periodic()
-- 	 XPLMSpeakString("November 7 victor delta, fly heading 2 4 0.")
-- end
-- 
-- do_sometimes("periodic()")