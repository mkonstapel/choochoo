const RAIL_STATION_RADIUS = 4;
const RAIL_STATION_WIDTH = 3;
const RAIL_STATION_PLATFORM_LENGTH = 4;
const RAIL_STATION_LENGTH = 7; // actual building and rails plus room for entrance/exit

require("builder_main.nut");
require("builder_misc.nut");
require("builder_cargo.nut");
require("builder_network.nut");
require("builder_road.nut");
require("builder_stations.nut");
require("builder_track.nut");
require("builder_trains.nut");

/**
 * Returns the proper direction for a station at a, with the tracks heading to b.
 */
function StationDirection(a, b) {
	local dx = AIMap.GetTileX(a) - AIMap.GetTileX(b);
	local dy = AIMap.GetTileY(a) - AIMap.GetTileY(b);
	
	if (abs(dx) > abs(dy)) {
		return dx > 0 ? Direction.SW : Direction.NE;
	} else {
		return dy > 0 ? Direction.SE : Direction.NW;
	}
}

/**
 * Find a site for a station at the given town.
 */
function FindStationSite(town, stationRotation, destination) {
	local location = AITown.GetLocation(town);
	
	local area = AITileList();
	SafeAddRectangle(area, location, 20);
	
	// only tiles that "belong" to the town
	area.Valuate(AITile.GetClosestTown)
	area.KeepValue(town);
	
	// must accept passengers
	// we can capture more production by joining bus stations 
	area.Valuate(CargoValue, stationRotation, [0, 0], [2, RAIL_STATION_PLATFORM_LENGTH], PAX, RAIL_STATION_RADIUS, true);
	area.KeepValue(1);
	
	// any production will do (we can capture more with bus stations)
	// but we need some, or we could connect, for example, a steel mill that only accepts passengers
	area.Valuate(AITile.GetCargoProduction, PAX, 1, 1, RAIL_STATION_RADIUS);
	area.KeepAboveValue(0);
	
	// room for a station - try to find a flat area first
	local flat = AIList();
	flat.AddList(area);
	// flat.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], true);
	for (local tile = flat.Begin(); flat.HasNext(); tile = flat.Next()) {
		flat.SetValue(tile, IsBuildableRectangle(tile, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], true) ? 1 : 0);
	}
	
	flat.KeepValue(1);
	
	if (flat.Count() > 0) {
		area = flat;
	} else {
		// try again, with terraforming
		// area.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], false);
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			area.SetValue(tile, IsBuildableRectangle(tile, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], false) ? 1 : 0);
		}
		area.KeepValue(1);
	}
	
	// pick the tile closest to the crossing
	//area.Valuate(AITile.GetDistanceManhattanToTile, destination);
	//area.KeepBottom(1);
	
	// pick the tile closest to the city center
	area.Valuate(AITile.GetDistanceManhattanToTile, location);
	area.KeepBottom(1);
	
	return area.IsEmpty() ? null : area.Begin();
}

function IsBuildableRectangle(location, rotation, from, to, mustBeFlat) {
	// check if the area is clear and flat
	// TODO: don't require it to be flat, check if it can be leveled
	local coords = RelativeCoordinates(location, rotation);
	local height = AITile.GetMaxHeight(location);
	
	for (local x = from[0]; x < to[0]; x++) {
		for (local y = from[1]; y < to[1]; y++) {
			local tile = coords.GetTile([x, y]);
			local flat = AITile.GetMaxHeight(tile) == height && AITile.GetMinHeight(tile) == height && AITile.GetMaxHeight(tile) == height;
			if (!AITile.IsBuildable(tile) || (mustBeFlat && !flat)) {
				return false;
			}
			
			local area = AITileList();
			SafeAddRectangle(area, tile, 1);
			area.Valuate(AITile.GetMinHeight);
			area.KeepAboveValue(height - 2);
			area.Valuate(AITile.GetMaxHeight);
			area.KeepBelowValue(height + 2);
			area.Valuate(AITile.IsBuildable);
			area.KeepValue(1);
			
			local flattenable = (
				area.Count() == 9 &&
				abs(AITile.GetMinHeight(tile) - height) <= 1 &&
				abs(AITile.GetMaxHeight(tile) - height) <= 1);
			
			if (!AITile.IsBuildable(tile) || !flattenable || (mustBeFlat && !flat)) {
				return false;
			}
		}
	}
	
	return true;
}

function CargoValue(location, rotation, from, to, cargo, radius, accept) {
	// check if any tile in the rectangle has >= 8 cargo acceptance/production
	local f = accept ? AITile.GetCargoAcceptance : AITile.GetCargoProduction;
	local coords = RelativeCoordinates(location, rotation);
	for (local x = from[0]; x < to[0]; x++) {
		for (local y = from[1]; y < to[1]; y++) {
			local tile = coords.GetTile([x, y]);
			if (f(tile, cargo, 1, 1, radius) > 7) {
				return 1;
			}
		}
	}
	
	return 0;
}
