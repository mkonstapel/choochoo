/**
 * Return the tile at x, y coordinates offset from origin.
 */
function GetTile(origin, coordinates) {
	return origin + AIMap.GetTileIndex(coordinates[0], coordinates[1]);
}

/**
 * Return the tile one step away from the given tile in the given direction.
 */
function Step(tile, direction) {
	local offset;
	switch (direction) {
		case Direction.N:  offset = [-1,-1]; break;
		case Direction.E:  offset = [-1, 1]; break;
		case Direction.S:  offset = [ 1, 1]; break;
		case Direction.W:  offset = [ 1,-1]; break;
		case Direction.NE: offset = [-1, 0]; break;
		case Direction.NW: offset = [ 0,-1]; break;
		case Direction.SE: offset = [ 0, 1]; break;
		case Direction.SW: offset = [ 1, 0]; break;
	}
	
	return GetTile(tile, offset);
}

/**
 * 2-platform terminus station
 */
class StationTypeA {
	
	static PLATFORM_LENGTH = 3;

	location = null;
	
	constructor(location) {
		this.location = location;
	}
	
	function GetEntrance() {
		// see which way the station is oriented
		local directions = [
			Direction.SE,
			Direction.SW,
			Direction.NW,
			Direction.NE,
		];
		
		local candidates = [
			GetTile(location, [0, PLATFORM_LENGTH+1]),
			GetTile(location, [PLATFORM_LENGTH+1, 1]),
			GetTile(location, [ 1,-2]),
			GetTile(location, [-2, 0])
		];
		
		foreach (i, c in candidates) {
			if (HasCorrectSignal(c, directions[i])) {
				return [Step(c, directions[i]), c];
			}
		}
		
		throw "Station has no entrance!";
	}
	
	function GetExit() {
		// see which way the station is oriented
		local directions = [
			Direction.SE,
			Direction.SW,
			Direction.NW,
			Direction.NE,
		];
		
		local reverse = [
			Direction.NW,
			Direction.NE,
			Direction.SE,
			Direction.NW,
		];
		
		local candidates = [
			GetTile(location, [1, PLATFORM_LENGTH+1]),
			GetTile(location, [PLATFORM_LENGTH+1, 0]),
			GetTile(location, [ 0,-2]),
			GetTile(location, [-2, 1])
		];
		
		foreach (i, c in candidates) {
			if (HasCorrectSignal(c, reverse[i])) {
				return [c, Step(c, directions[i])];
			}
		}
		
		throw "Station has no exit!";
	}
	
	function GetReservedEntranceSpace() {
		return ReserveSpace(GetEntrance(), GetExit());
	}
	
	function GetReservedExitSpace() {
		return ReserveSpace(GetExit(), GetEntrance());
	}
	
	/**
	 * Return a rectangle of reserved space for entrance/exit a, away from exit/entrance b.
	 */
	function ReserveSpace(a, b) {
		
	}
	
	function HasCorrectSignal(tile, direction) {
		return AIRail.GetSignalType(tile, Step(tile, direction)) == AIRail.SIGNALTYPE_PBS &&
		AITile.GetOwner(tile) == AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	}
	
}

/**
 * 1-platform RoRo station
 */
class StationTypeB {
	
	static PLATFORM_LENGTH = 3;

	location = null;
	
	constructor(location) {
		this.location = location;
	}
	
	function GetEntrance() {
		return [GetTile(location, [4,0]), GetTile(location, [3,0])];
	}
	
	function GetExit() {
		return [GetTile(location, [-1,0]), GetTile(location, [-2,0])];
	}
	
}

class Crossing {
	
	location = null;
	
	constructor(location) {
		this.location = location;
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
		
		return [GetTile(location, a), GetTile(location, b)];
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
		
		return [GetTile(location, a), GetTile(location, b)];
	}
	
}
