#!/usr/bin/env lua

function printf(s, ...)
    return print(s:format(...))
end 

-- Define math.pow for lua >= 5.3
if math.pow == nil then
    math.pow = function(x,y)
        return x^y
    end
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

printf("One degree longitude at 0 degrees latitude is %0.4f nm",
	   haversine_pos({lat=0, lon=0}, {lat=0, lon=1}))
printf("One degree longitude at 48 degrees latitude is %0.4f nm",
	   haversine_pos({lat=48, lon=-122}, {lat=48, lon=-121}))
printf("One degree longitude at 47 degrees latitude is %0.4f nm",
	   haversine_pos({lat=47, lon=-122}, {lat=47, lon=-121}))
printf("One degree longitude at 89 degrees latitude is %0.4f nm",
	   haversine_pos({lat=89, lon=60}, {lat=89, lon=61}))

printf("One degree latitude at (0,0) is %0.4f nm",
	   haversine_pos({lat=0, lon=0}, {lat=1, lon=0}))
printf("One degree latitude at (47,-122) is %0.4f nm",
	   haversine_pos({lat=47, lon=-122}, {lat=48, lon=-122}))
printf("One degree latitude at (-74,60) is %0.4f nm",
	   haversine_pos({lat=-74, lon=60}, {lat=-75, lon=60}))
