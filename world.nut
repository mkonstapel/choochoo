class World {
	stations = {};	// by tile
	crossings = {};	// by tile
	towns = {};		// town ID to station
}

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
	
}

class TerminusStation extends WorldObject {
	
	platformLength = null;
	
	constructor(location, rotation, platformLength) {
		WorldObject.constructor(location, rotation);
		this.platformLength = platformLength;
	}
	
	function GetEntrance() {
		return TileStrip([0, platformLength + 2], [0, platformLength + 1]);
	}
	
	function GetExit() {
		return TileStrip([1, platformLength + 1], [1, platformLength + 2]);
	}
	
	function GetReservedEntranceSpace() {
		return TileStrip([0, platformLength], [0, platformLength + 4]);
	}

	function GetReservedExitSpace() {
		return TileStrip([1, platformLength], [1, platformLength + 4]);
	}
	
}

class Network {
	
	railType = null;
	blockSize = null;
	cheap = null;
	stations = null;
	depots = null;
	trains = null;
	
	constructor(railType, blockSize, cheap = false) {
		this.railType = railType;
		this.blockSize = blockSize;
		this.cheap = cheap;
		this.stations = [];
		this.depots = [];
		this.trains = [];
	}
	
}