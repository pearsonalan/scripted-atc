#!/usr/bin/env lua

-- Define loadstring to support later versions of Lua
if loadstring == nil then
    loadstring = function (s)
        return load(s)
    end
end

-- Define math.pow for lua >= 5.3
if math.pow == nil then
    math.pow = function(x,y)
        return x^y
    end
end

local debug_print = false

function dprintf(s, ...)
    if debug_print then
        return print(s:format(...))
    end
end 

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[copy(k)] = copy(v) end
    return res
end

function pos_to_string(pos) 
    return string.format("{lat=%0.4f, lon=%0.4f, alt=%0.1f}",
                         pos.lat, pos.lon, pos.alt)
end

function set_alt(pos, alt)
    pos.alt = alt
    return pos
end

function haversine(lat1, lon1, lat2, lon2) 
    -- Radius of Earth in nautical miles
    local radius = 3440.1

    -- distance between latitudes  and longitudes 
    local dLat = (lat2 - lat1) * math.pi / 180.0
    local dLon = (lon2 - lon1) * math.pi / 180.0 

    -- convert to radians 
    lat1 = lat1 * math.pi / 180.0 
    lat2 = lat2 * math.pi / 180.0 

    -- apply formulae 
    local a = math.pow(math.sin(dLat / 2), 2) +  
              math.pow(math.sin(dLon / 2), 2) *  
              math.cos(lat1) * math.cos(lat2); 
    local c = 2 * math.asin(math.sqrt(a)); 
    return radius * c; 
end 

function haversine_pos(from, to) 
    return haversine(from.lat, from.lon, to.lat, to.lon)
end

function interpolate(from, to, fraction)
    return {lat=from.lat + (to.lat - from.lat) * fraction,
            lon=from.lon + (to.lon - from.lon) * fraction,
            alt=from.alt + (to.alt - from.alt) * fraction}
end

-- returns the determinant of a 2x2 matrix
function determinant(m) 
    -- print("  M = " .. dump(m))
    local det = m[1][1] * m[2][2] - m[1][2] * m[2][1]
    -- print("  det = " .. det)
    return det
end

-- returns the sign of the determinant of a 2x2 matrix
function determinant_sign(m)
    local d = determinant(m)
    if d < 0 then
        return -1
    elseif d > 0 then
        return 1
    else
        return 0
    end
end

-- Determines which "side" a point is of a line
-- return 1, 0 or -1
--
-- line is a table with .a and .b representing two points, each
--    having .lat and .lon) on the line
-- point is a location with .lat and .lon
--
function side(line, point)
    return determinant_sign{{line.b.lat - line.a.lat, point.lat - line.a.lat},
                            {line.b.lon - line.a.lon, point.lon - line.a.lon}}
end

-- Returns true if line segments s1 and s2 intersect
--
-- Segments are defined by points s.a and s.b where each
-- point, p, has p.lat and p.lon
function intersect(s1, s2)
    local ds0 = determinant_sign{{s1.a.lat - s2.a.lat, s1.b.lat - s2.a.lat},
                                 {s1.a.lon - s2.a.lon, s1.b.lon - s2.a.lon}}
    local ds1 = determinant_sign{{s1.a.lat - s2.b.lat, s1.b.lat - s2.b.lat},
                                 {s1.a.lon - s2.b.lon, s1.b.lon - s2.b.lon}}
    local ds2 = determinant_sign{{s2.a.lat - s1.a.lat, s2.b.lat - s1.a.lat},
                                 {s2.a.lon - s1.a.lon, s2.b.lon - s1.a.lon}}
    local ds3 = determinant_sign{{s2.a.lat - s1.b.lat, s2.b.lat - s1.b.lat},
                                 {s2.a.lon - s1.b.lon, s2.b.lon - s1.b.lon}}
    -- dprintf("  s0=%d, s1=%d, s2=%d, s3=%d", ds0, ds1, ds2, ds3)
    if ds0 ~= ds1 and ds2 ~= ds3 then
        -- dprintf("  INTERSECTION detected!!")
        return true
    end
    return false
end

local csv_file_

function print_csv(pos, label, color)
    if csv_file_ == nil then
        csv_file_ = io.open("flight.csv", "w")
        csv_file_:write("lat,lng,name,color,note\n")
    end
    csv_file_:write(string.format("%0.5f,%0.5f,%s,%s\n", pos.lat, pos.lon, label, color))
end

--
-- GLOBAL STATE
--

local conditions_ = {}
local current_pos_ = nil
local prev_pos_ = nil
local time_ = 0
local last_transmission_ = 0
local output_ = nil
local contacted_atc_on_ = nil
local contacted_atc_time_ = 0

--
-- CONDITION REGISTRATION / TESTING
--

function add_condition(cond, handler) 
    local cond_fn, hander_fn, err
    cond_fn, err = loadstring("return function() return " .. cond .. "; end")
    if err ~= nil then
        error(err)
    end
    handler_fn, err = loadstring("return function() " .. handler .. "; end")
    if err ~= nil then
        error(err)
    end
    table.insert(conditions_, {desc=cond, cond=cond_fn(),
                               triggered=false, handler=handler_fn()})
end

function test_conditions(pos)
    current_pos_ = pos
    output_ = ""
    for k, condition in ipairs(conditions_) do
        if not condition.triggered then
            dprintf("Evaluating %s", condition.desc)
            result = condition["cond"]()
            if result then
                dprintf("Condition %s is triggered", condition.desc)
                condition["handler"]()
                condition.triggered = true
            end
            -- only test the next un-triggered condition
            break
        end
    end
    prev_pos_ = pos
end

function show_conditions()
    for k, condition in ipairs(conditions_) do
        dprintf(" - %s => %s", condition.desc, condition.triggered)
    end
end


local ScriptedATC = (function () 
    local load_script = function(script_file) 
        local file = io.open(script_file, "r")
        if file == nil then
            error(string.format("Cannot read script from %s", script_file))
        end
        while true do
            local line = file:read()
            if line == nil then break end
            dprintf("SCRIPT: %s", line)
            local start_pos, end_pos, condition, action = string.find(line, "WHEN (.+) THEN (.+)")
            if start_pos == nil then
                loadstring(line)()
            else
                dprintf("COND: %s; ACTION: %s", condition, action)
                add_condition(condition, action)
            end
        end
    end

    return {load_script=load_script}
end)()

--
-- CONDITION FUNCTIONS
--

function distance_from(loc)
    -- dprintf("Evaluating distance from %s to %s", dump(current_pos_), dump(loc))
    local dist = haversine_pos(loc, current_pos_)
    -- dprintf("dist to %s = %0.2f", dump(loc), dist)
    return dist 
end

function crossed_gate(gate)
    return intersect(gate, {a=prev_pos_, b=current_pos_})
end

function altitude()
    return current_pos_.alt
end

function since_last_transmission()
    return time_ - last_transmission_
end

function since_last_resposne()
    return time_ - contacted_atc_time_
end

function contacted_atc_on(frequency)
    return contacted_atc_on_ == frequency
end

-- 
-- ACTIONS
--

function say(f)
    output_ = output_ .. f .. " "
    print(string.format("[t=%d, pos=%s] SAY: %s",
          math.floor(time_), pos_to_string(current_pos_), f))
    if XPLANE_VERSION ~= nil then
        XPLMSpeakString("November 7 victor delta, " .. f)
    end
    last_transmission_ = time_
end

--
-- Radio handlers
--

-- Converts a frequency expressed as an integer in Hz to a string
-- in KHz.
function frequency_to_string(freq)
    return string.format("%d.%02d", freq / 100, freq % 100)
end

function register_radio_handler()
    -- DataRefs
    local audio_panel_out_data_ref = nil
    local com1_freq_hz_data_ref = nil
    local com2_freq_hz_data_ref = nil

    function read_radio_data_refs()
        return XPLMGetDatai(audio_panel_out_data_ref), 
               XPLMGetDatai(com1_freq_hz_data_ref),
               XPLMGetDatai(com2_freq_hz_data_ref)
    end

    audio_panel_out_data_ref = XPLMFindDataRef("sim/cockpit/switches/audio_panel_out")
    if audio_panel_out_data_ref == nil then
        error("cannot find DataRef for audio_panel_out")
    end

    com1_freq_hz_data_ref = XPLMFindDataRef("sim/cockpit/radios/com1_freq_hz")
    if com1_freq_hz_data_ref == nil then
        error("cannot find DataRef for com1_freq_hz")
    end

    com2_freq_hz_data_ref = XPLMFindDataRef("sim/cockpit/radios/com2_freq_hz")
    if com2_freq_hz_data_ref == nil then
        error("cannot find DataRef for com2_freq_hz")
    end

    function contact_atc_end() 
        local selected_com_out, com1_freq_hz, com2_freq_hz = read_radio_data_refs()
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
            contacted_atc_on_ = frequency_to_string(frequency)
            contacted_atc_time_ = time_
        end
    end

    print("Creating command for scripted atc")
    create_command("FlyWithLua/ScriptedATC/ContactATC", "Contact ATC in Script",
                   "", "", "contact_atc_end()")
end

--
-- TEST DRIVERS
-- 

function fly_leg(to, groundspeed, first) 
    local start_pos = current_pos_
    local start_time = time_
    local distance = haversine_pos(current_pos_, to) 
    local ete_hrs = distance / groundspeed
    local ete_sec = ete_hrs * 3600

    dprintf("LEG: Flying from %s to %s", pos_to_string(current_pos_),
          pos_to_string(to))
    dprintf("LEG: Distance is %0.1f nm", distance)
    dprintf("LEG: ETE is %0.4f hrs (%0.1f seconds)", ete_hrs, ete_sec)

    function process_location(time, pos) 
        time_ = time
        dprintf("t = %d sec: pos = %s", math.floor(time), pos_to_string(pos))
        test_conditions(pos)
        show_conditions()

        if output_ == "" then
            print_csv(pos, string.format("%d", math.floor(time)), "#FF00FF")
        else
            print_csv(pos, output_, "#00FF00")
        end
    end

    if first then
        process_location(time_, start_pos)
    end

    for t = 15,ete_sec,15 do
        local pos = interpolate(start_pos, to, t / ete_sec)
        process_location(start_time + t, pos)
    end
    time_ = start_time + ete_sec
end

function fly(legs)
    current_pos_ = legs[1].from
    prev_pos_ = legs[1].from
    for i, leg in ipairs(legs) do
        fly_leg(leg.to, leg.groundspeed, i == 1)
    end
end

--
-- FlyWithLua / X-Plane handler
--
function register_xplane_handler()
    function meters_to_feet(meters)
        return meters * 3.28084
    end

    local TRANSPARENT_PERCENT = 0.55   -- the darkness of the windows background
    local FRAME_WIDTH = 450
    local LINE_HEIGHT = 20

    -- DataRefs
    local latitude_data_ref = nil
    local longitude_data_ref = nil
    local altitude_data_ref = nil

    -- Values of DataRefs updated every second by read_data_refs
    local latitude = 0.0
    local longitude = 0.0
    local altitude = 0.0

    function read_data_refs()
        latitude = XPLMGetDataf(latitude_data_ref)
        longitude = XPLMGetDataf(longitude_data_ref)
        altitude = meters_to_feet(XPLMGetDataf(altitude_data_ref))
    end

    function ScriptedATC_check_conditions()
        time_ = os.clock()
        read_data_refs()
        dprintf("%d @ %0.4f,%0.4f,%d", time_, latitude, longitude, altitude)
        test_conditions{lat=latitude, lon=longitude, alt=altitude}
        -- show_conditions()
    end

    function ScriptedATC_show_conditions()
        local posx = SCREEN_WIDTH - FRAME_WIDTH
        local posy = SCREEN_HIGHT - 120          -- SIC

        XPLMSetGraphicsState(0,0,0,1,1,0,0)
        glColor4f(0,0,0,TRANSPARENT_PERCENT)
        glRectf(posx-10, posy+10, posx + FRAME_WIDTH + 20, posy - 10 * LINE_HEIGHT - 20)
        for k, condition in ipairs(conditions_) do
            if condition.triggered then
                glColor4f(0.3,1.0,0.3,1)
            else
                glColor4f(0.8,0.8,0.8,1)
            end
            draw_string_Helvetica_18(posx, posy - k * LINE_HEIGHT, condition.desc)
        end
    end

    print("Initializing X-Plane Scripted ATC Handler")

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

    do_often("ScriptedATC_check_conditions()")
    do_every_draw("ScriptedATC_show_conditions()")
end

function simulate_flight()
    fly{{from=KBFI, to=set_alt(copy(ZIGED), 3000), groundspeed=90},
        {to={lat=47.2843, lon=-122.4445, alt=3000}, groundspeed=120},
        {to={lat=47.41, lon=-122.46, alt=3000}, groundspeed=120},
        {to={lat=47.3762, lon=-122.5563, alt=2000}, groundspeed=120},
        {to=KTIW, groundspeed=80}}
end

if SCRIPT_DIRECTORY == nil then
    SCRIPT_DIRECTORY = ".\\"
end

ScriptedATC.load_script(SCRIPT_DIRECTORY .. "contact-atc.script")

-- If not running under FlyWithLua, simulate a flight
if XPLANE_VERSION == nil then
    simulate_flight()
end

-- If running under FlyWithLua, register handlers
if XPLANE_VERSION ~= nil then
    print("Running scripted-atc in FlyWithLua")
    register_radio_handler()
    register_xplane_handler()
end