#!/usr/bin/env lua

local JAWBN={lat=48.03, lon=-122.83}
local LOFAL={lat=47.85, lon=-122.68}
local VAR = -16

function printf(s, ...)
    return print(s:format(...))
end 

function to_radians(deg)
	return deg * math.pi / 180.0
end

function haversine(lat1, lon1, lat2, lon2) 
    -- Radius of Earth in nautical miles
    local radius = 3440.1

    -- difference between latitudes and longitudes 
    local delta_lat = to_radians(lat2 - lat1)
    local delta_lon = to_radians(lon2 - lon1)

    -- apply formulae 
    local a = math.pow(math.sin(delta_lat / 2), 2) +  
              math.pow(math.sin(delta_lon / 2), 2) *  
              math.cos(to_radians(lat1)) * math.cos(to_radians(lat2)); 
    local c = 2 * math.asin(math.sqrt(a)); 
    return radius * c; 
end 

function haversine_pos(from, to) 
    return haversine(from.lat, from.lon, to.lat, to.lon)
end

function bearing(from, to)
    local dLon = to_radians(to.lon - from.lon)
	local y = math.sin(dLon) * math.cos(to_radians(to.lat))
	local x = (math.cos(to_radians(from.lat)) * math.sin(to_radians(to.lat))) -
			  (math.sin(to_radians(from.lat)) * math.cos(to_radians(to.lat)) * math.cos(dLon))
	local angle_radians = math.atan2(y, x)
	return ((angle_radians * 180 / math.pi) + 360) % 360  -- in degrees
end

-- Returns the magnetic heading from the "from" location to the "to" location.
-- This is the true bearing adjusted for magnetic variation
function magnetic_heading(from, to)
	return (bearing(from, to) + VAR + 360) % 360
end

-- Returns the "ATC assigned" heading from the "from" location to the "to" location.
-- ATC typically gives headings in even "10's". Instead of saying "fly heading 272" they
-- will say "fly heading 270".  This returns the magnetic heading rounded to the 
-- nearest multiple of 10.
function heading(from, to)
	return math.floor((magnetic_heading(from, to) + 5) / 10) * 10
end

printf("Haversine distance from LOFAL to JAWBN is %0.2f", haversine_pos(LOFAL, JAWBN))
printf("True Course from LOFAL to JAWBN is %0.2f", bearing(LOFAL, JAWBN))
printf("Magnetic Heading from LOFAL to JAWBN is %0.2f", magnetic_heading(LOFAL, JAWBN))
printf("ATC Heading from LOFAL to JAWBN is %0d", heading(LOFAL, JAWBN))
