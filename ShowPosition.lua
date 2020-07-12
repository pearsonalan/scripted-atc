-- DataRef("heading_bug", "sim/cockpit/autopilot/heading", "readonly" )
-- DataRef("latitude", "sim/flightmodel/position/latitude", "readonly" )
-- DataRef("longitude", "sim/flightmodel/position/longitude", "readonly" )
-- DataRef("altitude", "sim/flightmodel/position/elevation", "readonly" )
DataRef("selected_com_out", "sim/cockpit/switches/audio_panel_out", "readonly")
DataRef("com1_freq_hz", "sim/cockpit/radios/com1_freq_hz", "readonly")
DataRef("com2_freq_hz", "sim/cockpit/radios/com2_freq_hz", "readonly")

local HeadingView = (function ()
	function meters_to_feet(meters)
		return meters * 3.28084
	end

	-- DataRefs
	local magnetic_heading_data_ref = nil
	local latitude_data_ref = nil
	local longitude_data_ref = nil
	local altitude_data_ref = nil

	-- Values of DataRefs updated every second by read_data_refs
	local magnetic_heading = 0.0
	local latitude = 0.0
	local longitude = 0.0
	local altitude = 0.0

	function HeadingView_read_data_refs()
		magnetic_heading = XPLMGetDataf(magnetic_heading_data_ref)
		latitude = XPLMGetDataf(latitude_data_ref)
		longitude = XPLMGetDataf(longitude_data_ref)
		altitude = XPLMGetDataf(altitude_data_ref)
	end

	function HeadingView_draw_position()
		local posx = SCREEN_WIDTH - 200
		local posy = SCREEN_HIGHT - 20          -- SIC
		local line_height = 20

		draw_string_Helvetica_18(posx, posy,
								 "HDG: " .. math.floor(magnetic_heading + 0.5))
		draw_string_Helvetica_18(posx, posy - line_height,
								 "LAT: " .. string.format("%0.4f", latitude))
		draw_string_Helvetica_18(posx, posy - 2 * line_height,
								 "LON: " .. string.format("%0.4f", longitude))
		draw_string_Helvetica_18(posx, posy - 3 * line_height,
								 "ALT: " .. string.format("%d", meters_to_feet(altitude)))
	end

	print("Initializing HeadingView")

	magnetic_heading_data_ref = XPLMFindDataRef("sim/cockpit/autopilot/heading_mag")
	if magnetic_heading_data_ref == nil then
		error("cannot find DataRef for magnetic_heading")
	end

	latitude_data_ref = XPLMFindDataRef("sim/flightmodel/position/latitude")
	if latitude_data_ref == nil then
		error("cannot find DataRef for latitude")
	end

	longitude_data_ref = XPLMFindDataRef("sim/flightmodel/position/longitude")
	if longitude_data_ref == nil then
		error("cannot find DataRef for longitude")
	end

	altitude_data_ref = XPLMFindDataRef("sim/flightmodel/position/elevation")
	if altitude_data_ref == nil then
		error("cannot find DataRef for altitude")
	end

	do_every_frame("HeadingView_read_data_refs()")
	do_every_draw("HeadingView_draw_position()")
end)()

local atc_debug_string = "ATC Result"
local key_press_time = os.clock()

function show_atc_result()
	if atc_debug_string ~= "" then
		glColor4f(255, 255, 255, 255)
		draw_string_Helvetica_18(50, SCREEN_HIGHT-130, atc_debug_string)
	end
end

do_every_draw("show_atc_result()")

function reset_atc_result()
	if os.clock() - key_press_time > 1.0 then
		atc_debug_string = ""
	end
end

do_often("reset_atc_result()")

-- function keystroke_handler()
-- 	if VKEY == 13 then
-- 		atc_debug_string = "Return pressed"
-- 		key_press_time = os.clock()
-- 		RESUME_KEY = true
-- 	end
-- end
-- 
-- do_on_keystroke("keystroke_handler()")

-- Converts a frequency expressed as an integer in Hz to a string
-- in KHz.
function frequency_to_string(freq)
	return string.format("%d.%02d", freq / 100, freq % 100)
end

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
		local msg = string.format("%s frequency is %s", com,
								  frequency_to_string(frequency))
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