const RAIL_STATION_RADIUS = 4;
const RAIL_STATION_WIDTH = 3;
const RAIL_STATION_PLATFORM_LENGTH = 4;
const RAIL_STATION_LENGTH = 7; // actual building and rails plus room for entrance/exit

const BRANCH_STATION_WIDTH = 2;
const BRANCH_STATION_PLATFORM_LENGTH = 3;
const BRANCH_STATION_LENGTH = 3;

require("builder_main.nut");
require("builder_misc.nut");
require("builder_cargo.nut");
require("builder_network.nut");
require("builder_branch.nut");
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

function FindMainlineStationSite(town, stationRotation, destination) {
	return FindStationSite(town, stationRotation, destination, RAIL_STATION_WIDTH, RAIL_STATION_LENGTH, RAIL_STATION_PLATFORM_LENGTH);
}

function FindBranchStationSite(town, stationRotation, destination) {
	// don't increase BRANCH_STATION_LENGTH because that's the area we flatten,
	// but we do need some space to allow the track to get in, and ideally out the back, too
	return FindStationSite(town, stationRotation, destination, BRANCH_STATION_WIDTH, BRANCH_STATION_LENGTH+2, BRANCH_STATION_PLATFORM_LENGTH, 4);
}

/**
 * Find a site for a station at the given town.
 */
function FindStationSite(town, stationRotation, destination, width, length, platformLength, exitSpace=0) {
	local location = AITown.GetLocation(town);
	
	local area = AITileList();
	SafeAddRectangle(area, location, 20);
	
	// only tiles that "belong" to the town
	area.Valuate(AITile.GetClosestTown)
	area.KeepValue(town);
	
	// must accept passengers
	// we can capture more production by joining bus stations 
	area.Valuate(CargoValue, stationRotation, [0, 0], [2, platformLength], PAX, RAIL_STATION_RADIUS, true);
	area.KeepValue(1);
	
	// any production will do (we can capture more with bus stations)
	// but we need some, or we could connect, for example, a steel mill that only accepts passengers
	area.Valuate(AITile.GetCargoProduction, PAX, 1, 1, RAIL_STATION_RADIUS);
	area.KeepAboveValue(0);
	
	// room for a station - try to find a flat area first
	local flat = AIList();
	flat.AddList(area);
	// flat.Valuate(IsBuildableRectangle, stationRotation, [0, -exitSpace], [width, length], true);
	for (local tile = flat.Begin(); flat.HasNext(); tile = flat.Next()) {
		flat.SetValue(tile, IsBuildableRectangle(tile, stationRotation, [0,  -exitSpace], [width, length], true) ? 1 : 0);
	}
	
	flat.KeepValue(1);
	
	if (flat.Count() > 0) {
		area = flat;
	} else {
		// try again, with terraforming
		// area.Valuate(IsBuildableRectangle, stationRotation, [0, -exitSpace], [width, length], false);
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			area.SetValue(tile, IsBuildableRectangle(tile, stationRotation, [0, -exitSpace], [width, length], false) ? 1 : 0);
		}
		area.KeepValue(1);
	}

	if (!area.IsEmpty()) {
		area.Valuate(LakeDetector, destination);
		area.KeepValue(0);

		if (area.IsEmpty()) {
			Warning("LakeDetector rejected " + AITown.GetName(town));
		}
	}
	
	// pick the tile closest to the crossing
	//area.Valuate(AITile.GetDistanceManhattanToTile, destination);
	//area.KeepBottom(1);

	// pick the tile closest to the city center
	area.Valuate(AITile.GetDistanceManhattanToTile, location);
	area.KeepBottom(1);
	
	return area.IsEmpty() ? null : area.Begin();
}

function LakeDetector(tile, destination) {
	// check the edges of the rectangle defined by the tile and destination
	// return true if two opposing edges are blocked by water
	local x1 = AIMap.GetTileX(tile);
	local y1 = AIMap.GetTileY(tile);
	local x2 = AIMap.GetTileX(destination);
	local y2 = AIMap.GetTileY(destination);
	local xmin = min(x1, x2);
	local xmax = max(x1, x2);
	local ymin = min(y1, y2);
	local ymax = max(y1, y2);

	// at least allow some water, even if we are allowed no or only tiny bridges
	// 4 tiles probably means there's a way around somewhere
	// and otherwise we might never build anything
	local waterLimit = max(GetMaxBridgeLength() - 2, 4);
	local xminBlocked = _LakeDetectorEdge(xmin, ymin, xmin, ymax, waterLimit);
	local xmaxBlocked = _LakeDetectorEdge(xmax, ymin, xmax, ymax, waterLimit);
	if (xminBlocked && xmaxBlocked) {
		return 1;
	}

	local yminBlocked = _LakeDetectorEdge(xmin, ymin, xmax, ymin, waterLimit);
	local ymaxBlocked = _LakeDetectorEdge(xmin, ymax, xmax, ymax, waterLimit);
	return yminBlocked && ymaxBlocked ? 1 : 0;
}

function _LakeDetectorEdge(xmin, ymin, xmax, ymax, waterLimit) {
	if (!(xmin == xmax || ymin == ymax)) {
		throw "LakeDetectorEdge: not an edge";
	}

	if (!(xmin <= xmax && ymin <= ymax)) {
		throw  "LakeDetectorEdge: min > max";
	}

	local waterCount = 0;
	for (local x = xmin; x <= xmax; x++) {
		for (local y = ymin; y <= ymax; y++) {

			local t = AIMap.GetTileIndex(x, y);
			if (AITile.IsWaterTile(t)) {
				waterCount++;
			} else {
				waterCount = 0;
			}
			if (waterCount > waterLimit) {
				return true;
			}
		}
	}

	return false;
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
