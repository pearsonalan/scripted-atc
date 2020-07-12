#!/usr/bin/env lua

printf = function(s, ...)
            return io.write(s:format(...))
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
    -- printf("  s0=%d, s1=%d, s2=%d, s3=%d\n", ds0, ds1, ds2, ds3)
    if ds0 ~= ds1 and ds2 ~= ds3 then
        -- printf("  INTERSECTION detected!!\n")
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
            printf(" [evaluating %s]\n", condition.desc)
            result = condition["cond"]()
            if result then
                printf(" [condition %s is triggered]\n", condition.desc)
                condition["handler"]()
                condition.triggered = true
            end
            -- only test the next un-triggered condition
            break
        end
    end
end

function show_conditions()
    for k, condition in ipairs(conditions_) do
        printf(" - %s => %s\n", condition.desc, condition.triggered)
    end
end


--
-- CONDITION FUNCTIONS
--

function distance_from(loc)
    -- printf("Evaluating distance from %s to %s\n", dump(current_pos_), dump(loc))
    local dist = haversine_pos(loc, current_pos_)
    -- printf("dist to %s = %0.2f\n", dump(loc), dist)
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

-- 
-- ACTIONS
--

function say(f)
    output_ = output_ .. f .. " "
    printf("SAY: %s\n", f)
    last_transmission_ = time_
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

    printf("LEG: Flying from %s to %s\n", pos_to_string(current_pos_),
          pos_to_string(to))
    printf("LEG: Distance is %0.1f nm\n", distance)
    printf("LEG: ETE is %0.4f hrs (%0.1f seconds)\n", ete_hrs, ete_sec)

    function process_location(time, pos) 
        time_ = time
        printf("t = %d sec: pos = %s\n", time, pos_to_string(pos))
        test_conditions(pos)
        show_conditions()

        if output_ == "" then
            print_csv(pos, string.format("%d", time), "#FF00FF")
        else
            print_csv(pos, output_, "#00FF00")
        end

        prev_pos_ = pos
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
-- WELL-KNOWN LOCATIONS
--

KBFI = {lat=47.53, lon=-122.30, alt=18}
ZIGED = {lat=47.33, lon=-122.13}
KTIW = {lat=47.268, lon=-122.5781, alt=295}
SCENN = {lat=47.36, lon=-122.56}
COMMENCEMENT_BAY_GATE = {a={lat=47.31544, lon=-122.4262}, b={lat=47.26328, lon=-122.4276}}
SOUTH_VASHON_GATE = {a={lat=47.35, lon=-122.52}, b={lat=47.35, lon=-122.41}}
VASHON_GATE = {a={lat=47.39, lon=-122.52}, b={lat=47.39, lon=-122.41}}

function main()
    add_condition("altitude() > 600", "say(\"Contact departure on 119.2\")")
    add_condition("since_last_transmission() > 10", "say(\"Radar Contact. Seattle altimeter is 29.92\")")
    add_condition("distance_from(KBFI) > 5", "say(\"Climb and maintain 3000\")")
    add_condition("distance_from(ZIGED) < 2", "say(\"Fly heading 240\")")
    add_condition("crossed_gate(COMMENCEMENT_BAY_GATE)", "say(\"Turn right to 340\")")
    add_condition("crossed_gate(SOUTH_VASHON_GATE)", "say(\"Change to Seattle approach on 120.1\")")
    add_condition("since_last_transmission() > 10", "say(\"Seattle altimeter is 29.92\")")
    add_condition("crossed_gate(VASHON_GATE)", "say(\"Left turn to heading 240.\")")
    add_condition("distance_from(SCENN) < 2", "say(\"2 miles from SCENN. Join the localizer. Cross SCENN at 2000. Cleared ILS 17.\")")
    add_condition("distance_from(KTIW) < 5", "say(\"Contact Tacoma tower on 118.5\")")

    fly{{from=KBFI, to=set_alt(copy(ZIGED), 3000), groundspeed=90},
        {to={lat=47.2843, lon=-122.4445, alt=3000}, groundspeed=120},
        {to={lat=47.41, lon=-122.46, alt=3000}, groundspeed=120},
        {to={lat=47.3762, lon=-122.5563, alt=2000}, groundspeed=120},
        {to=KTIW, groundspeed=80}}
end

main()
