class RelativeCoordinates {

	static matrices = [
		// ROT_0
		[ 1, 0,
		  0, 1],

		// ROT_90
		[ 0,-1,
		  1, 0],

		// ROT_180
		[-1, 0,
		  0,-1],

		// ROT_270
		[ 0, 1,
		 -1, 0]
	];

	location = null;
	rotation = null;

	constructor(location, rotation = Rotation.ROT_0) {
		this.location = location;
		this.rotation = rotation;
	}

	function GetTile(coordinates) {
		local matrix = matrices[rotation];
		local x = coordinates[0] * matrix[0] + coordinates[1] * matrix[1];
		local y = coordinates[0] * matrix[2] + coordinates[1] * matrix[3];
		//Debug(coordinates[0] + "," + coordinates[1] + " -> " + x + "," + y);
		return location + AIMap.GetTileIndex(x, y);
	}

}

class WorldObject {

	relativeCoordinates = null;
	location = null;
	rotation = null;

	constructor(location, rotation = Rotation.ROT_0) {
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}

	function GetTile(coordinates) {
		return relativeCoordinates.GetTile(coordinates);
	}

	function TileStrip(start, end) {
		local tiles = [];

		local count, xstep, ystep;
		if (start[0] == end[0]) {
			count = abs(end[1] - start[1]);
			xstep = 0;
			ystep = end[1] < start[1] ? -1 : 1;
		} else {
			count = abs(end[0] - start[0]);
			xstep = end[0] < start[0] ? -1 : 1;
			ystep = 0
		}

		for (local i = 0, x  = start[0], y = start[1]; i <= count; i++, x += xstep, y += ystep) {
			tiles.append(GetTile([x, y]));
		}

		return tiles;
	}
}

class Crossing extends WorldObject {

	static WIDTH = 4;

	constructor(location) {
		WorldObject.constructor(location);
	}

	function GetEntrance(direction) {
		local a, b;

		switch (direction) {
			case Direction.NE: a = [-1, 1]; b = [0,1]; break;
			case Direction.SE: a = [ 1, 4]; b = [1,3]; break;
			case Direction.SW: a = [ 4, 2]; b = [3,2]; break;
			case Direction.NW: a = [ 2,-1]; b = [2,0]; break;
			default: throw "Invalid direction";
		}

		return TileStrip(a, b);
	}

	function GetExit(direction) {
		local a, b;

		switch (direction) {
			case Direction.NE: a = [0,2]; b = [-1, 2]; break;
			case Direction.SE: a = [2,3]; b = [ 2, 4]; break;
			case Direction.SW: a = [3,1]; b = [ 4, 1]; break;
			case Direction.NW: a = [1,0]; b = [ 1,-1]; break;
			default: throw "Invalid direction";
		}

		return TileStrip(a, b);
	}

	function GetReservedEntranceSpace(direction) {
		local a, b;

		switch (direction) {
			case Direction.NE: a = [-5, 1]; b = [0,1]; break;
			case Direction.SE: a = [ 1, 8]; b = [1,3]; break;
			case Direction.SW: a = [ 8, 2]; b = [3,2]; break;
			case Direction.NW: a = [ 2,-5]; b = [2,0]; break;
			default: throw "Invalid direction";
		}

		return TileStrip(a, b);
	}

	function GetReservedExitSpace(direction) {
		local a, b;

		switch (direction) {
			case Direction.NE: a = [0,2]; b = [-5, 2]; break;
			case Direction.SE: a = [2,3]; b = [ 2, 8]; break;
			case Direction.SW: a = [3,1]; b = [ 8, 1]; break;
			case Direction.NW: a = [1,0]; b = [ 1,-5]; break;
			default: throw "Invalid direction";
		}

		return TileStrip(a, b);
	}

	function CountConnections() {
		local count = 0;

		foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
			// check both the entrance and the exit, because in left hand drive, these are reversed
			local entrance = GetEntrance(d);
			local exit = GetExit(d);

			// TODO: this may be incorrect if another track runs right past the crossing
			if (AITile.GetOwner(entrance[0]) == COMPANY && AIRail.IsRailTile(entrance[0]) ||
				AITile.GetOwner(exit[1]) == COMPANY && AIRail.IsRailTile(exit[1])) {
				count++;
			}
		}

		return count;
	}

	function CountPotentialConnections() {
		// like CountConnections, but also counts unconnected (but still present) directions
		local count = 0;

		foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
			local entrance = GetEntrance(d);
			local exit = GetExit(d);

			// this looks at the other tile of the entrance/exit strip, which is present
			// as long as that direction hasn't been deconstructed
			if (AITile.GetOwner(entrance[1]) == COMPANY && AIRail.IsRailTile(entrance[1]) ||
				AITile.GetOwner(exit[0]) == COMPANY && AIRail.IsRailTile(exit[0])) {
				count++;
			}
		}

		return count;
	}

	function GetWaypointID() {
		local waypoints = [ [0,2], [0,1], [2,3], [1,3], [3,1], [3,2], [1,0], [2,0] ];
		foreach (tile in waypoints) {
			local waypointID = AIWaypoint.GetWaypointID(GetTile(tile));
			if (AIWaypoint.IsValidWaypoint(waypointID)) {
				return waypointID;
			}
		}

		return null;
	}

	function GetName() {
		local waypointID = GetWaypointID();
		if (waypointID != null) {
			return AIWaypoint.GetName(waypointID);
		}

		return "unnamed junction at " + TileToString(location);
	}

	function SetName(name) {
		local waypointID = GetWaypointID();
		if (waypointID != null) {
			return AIWaypoint.SetName(waypointID, name);
		}

		return null;
	}

	function UpdateName(_useCount = null) {
		// TODO: while still potentially being extended, prefer "junction"?
		// then downgrade to waypoint or upgrade to "crossing"?
		Debug("UpdateName for " + this);


		local waypointID = GetWaypointID();
		if (waypointID == null) return;

		local suffixesForCount = [
			null,
			["Stop"],
			["Waypoint"],
			["Junction", "Switch", "Points"],
			["Crossing", "Cross", "Union"]
		];

		local town = AITile.GetClosestTown(AIWaypoint.GetLocation(waypointID));
		local count = _useCount == null ? CountPotentialConnections() : _useCount;
		local suffixes = suffixesForCount[count];

		// we want "stable" names for the same number of exits, not cycle through
		// renaming from Crossing to Union to Cross, etc.
		foreach (suffix in suffixes) {
			if (EndsWith(AIWaypoint.GetName(waypointID), suffix)) {
				return;
			}
		}

		Shuffle(suffixes);
		foreach (suffix in suffixes) {
			local name = AITown.GetName(town) + " " + suffix;
			if (AIWaypoint.SetName(waypointID, name)) {
				return;
			}
		}

		if (count == 4) {
			// the names for 3 connections are also usable for 4 connections
			UpdateName(3);
		}
	}

	function _tostring() {
		return GetName();
	}

}

class TrainStation extends WorldObject {
	platformLength = null;

	constructor(location, rotation, platformLength) {
		WorldObject.constructor(location, rotation);
		this.platformLength = platformLength;
	}

	function AtLocation(location) {
		// deduce the type and rotation of an existing station
		local rotation;
		local direction = AIRail.GetRailStationDirection(location);
		if (direction == AIRail.RAILTRACK_NE_SW) {
			if (AIRail.IsRailStationTile(location + AIMap.GetTileIndex(1,0))) {
				rotation = Rotation.ROT_270;
			} else {
				rotation = Rotation.ROT_90;
			}
		} else if (direction == AIRail.RAILTRACK_NW_SE) {
			if (AIRail.IsRailStationTile(location + AIMap.GetTileIndex(0,1))) {
				rotation = Rotation.ROT_0;
			} else {
				rotation = Rotation.ROT_180;
			}
		} else {
			throw "no station at " + location;
		}


		local coordinates = RelativeCoordinates(location, rotation);
		local platformLength = 0;
		while (AIRail.IsRailStationTile(coordinates.GetTile([0, platformLength]))) {
			platformLength++;
		}

		if (AIRail.IsRailStationTile(coordinates.GetTile([1,1]))) {
			return TerminusStation(location, rotation, platformLength);
		} else if (AIRoad.IsRoadDepotTile(coordinates.GetTile([1,1]))) {
			return BranchStation(location, rotation, platformLength);
		} else {
			throw "cannot identify type of station at " + location;
		}
	}
}

class TerminusStation extends TrainStation {

	constructor(location, rotation, platformLength) {
		TrainStation.constructor(location, rotation, platformLength);
	}

	function _tostring() {
		return AIStation.GetName(AIStation.GetStationID(location));
	}

	function GetEntrance() {
		return TileStrip([0, platformLength + 2], [0, platformLength + 1]);
	}

	function GetExit() {
		return TileStrip([1, platformLength + 1], [1, platformLength + 2]);
	}

	function GetReservedEntranceSpace() {
		return TileStrip([0, platformLength], [0, platformLength + 2]);
	}

	function GetReservedExitSpace() {
		return TileStrip([1, platformLength], [1, platformLength + 2]);
	}

	function GetRearEntrance() {
		return TileStrip([1, -1], [1, 0]);
	}

	function GetRearExit() {
		return TileStrip([0, 0], [0, -1]);
	}

	function GetReservedRearEntranceSpace() {
		return TileStrip([1, -1], [1, -2]);
	}

	function GetReservedRearExitSpace() {
		return TileStrip([0, 0], [0, -2]);
	}

	function GetRoadDepot() {
		return GetTile([2,3]);
	}

	function GetRoadDepotExit() {
		return GetTile([2,2]);
	}
}

class BranchStation extends TrainStation {

	constructor(location, rotation, platformLength) {
		TrainStation.constructor(location, rotation, platformLength);
	}

	function _tostring() {
		return AIStation.GetName(AIStation.GetStationID(location));
	}

	function GetEntrance() {
		return TileStrip([0, platformLength+1], [0, platformLength]);
	}

	function GetExit() {
		return Swap(GetEntrance());
	}

	function GetReservedEntranceSpace() {
		// space for the road to exit
		// no longer needed now that we manually build a road/rail crossing if needed
		// return TileStrip([1, platformLength], [1, platformLength + 2]);
		return [];
	}

	function GetReservedExitSpace() {
		return GetReservedEntranceSpace();
	}

	function GetRearEntrance() {
		return TileStrip([0, -1], [0, 0]);
	}

	function GetRearExit() {
		return Swap(GetRearEntrance());
	}

	function GetReservedRearEntranceSpace() {
		return TileStrip([0, 0], [0, -2]);
	}

	function GetReservedRearExitSpace() {
		return GetReservedRearEntranceSpace();
	}

	function GetRoadDepot() {
		return GetTile([1,1]);
	}

	function GetRoadDepotExit() {
		return GetTile([1,2]);
	}
}

class Network {

	railType = null;
	rightSide = null;
	trainLength = null;
	minDistance = null;
	maxDistance = null;
	stations = null;
	depots = null;
	trains = null;

	constructor(railType, rightSide, trainLength, minDistance, maxDistance) {
		this.railType = railType;
		this.rightSide = rightSide;
		this.trainLength = trainLength;
		this.minDistance = minDistance;
		this.maxDistance = maxDistance;
		this.stations = [];
		this.depots = [];
		this.trains = [];
	}

}