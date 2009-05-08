// rotation, counterclockwise
ROT_0   <-	[ 1, 0,
			  0, 1];

ROT_90  <-	[ 0,-1,
			  1, 0];

ROT_180 <-	[-1, 0,
			  0,-1];

ROT_270 <-	[ 0, 1,
			 -1, 0];

class Builder extends Task {
	
	location = null;
	rotation = ROT_0;
	
	constructor(location, rotation = ROT_0) {
		this.location = location;
		this.rotation = rotation;
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
			Debug(x + "," + y);
			tiles.append(GetTile([x, y]));
		}
				
		return tiles;
	}
	
	function GetTile(coordinates) {
		local x = coordinates[0] * rotation[0] + coordinates[1] * rotation[1];
		local y = coordinates[0] * rotation[2] + coordinates[1] * rotation[3];
		//Debug(coordinates[0] + "," + coordinates[1] + " -> " + x + "," + y);
		return location + AIMap.GetTileIndex(x, y);
	}
	
	/**
	 * Build a non-diagonal segment of track.
	 */
	function BuildSegment(start, end) {
		local from, to;
		if (start[0] == end[0]) {
			from = [start[0], start[1] - 1];
			to = [end[0], end[1] + 1];
		} else {
			from = [start[0] - 1, start[1]];
			to = [end[0] + 1, end[1]];
		}
		
		BuildRail(from, start, to);
	}
	
	/**
	 * Build a straight piece of track, excluding 'from' and 'to'.
	 */
	function BuildRail(from, on, to) {
		AIRail.BuildRail(GetTile(from), GetTile(on), GetTile(to));
		CheckError();
	}
	
	/**
	 * Build a signal.
	 */
	function BuildSignal(tile, front) {
		AIRail.BuildSignal(GetTile(tile), GetTile(front), AIRail.SIGNALTYPE_PBS);
		CheckError();
	}
	
}

class BuildCrossing extends Builder {
	
	constructor(location) {
		Builder.constructor(location);
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
	
	function Run() {
		// four segments of track
		BuildSegment([0,1], [3,1]);
		BuildSegment([0,2], [3,2]);
		BuildSegment([1,0], [1,3]);
		BuildSegment([2,0], [2,3]);
		
		// outer diagonals (clockwise)
		BuildRail([1,0], [1,1], [0,1]);
		BuildRail([0,2], [1,2], [1,3]);
		BuildRail([3,2], [2,2], [2,3]);
		BuildRail([2,0], [2,1], [3,1]);
		
		// inner diagonals (clockwise)
		BuildRail([2,1], [1,1], [1,2]);
		BuildRail([1,1], [1,2], [2,2]);
		BuildRail([2,1], [2,2], [1,2]);
		BuildRail([1,1], [2,1], [2,2]);
		
		// signals (clockwise)
		BuildSignal([0,1], [-1, 1]);
		BuildSignal([0,2], [ 1, 2]);
		BuildSignal([1,3], [ 1, 4]);
		BuildSignal([2,3], [ 2, 2]);
		BuildSignal([3,2], [ 4, 2]);
		BuildSignal([3,1], [ 2, 1]);
		BuildSignal([2,0], [ 2,-1]);
		BuildSignal([1,0], [ 1, 1]);
	}
	
	function _tostring() {
		return "BuildCrossing";
	}
}

/**
 * 2-platform terminus station.
 */
class BuildTerminusStation extends Builder {
	
	platformLength = null;
	
	constructor(location, rotation, platformLength = 3) {
		Builder.constructor(location, rotation);
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
	
	function Run() {
		BuildPlatforms();
		
		local p = platformLength;
		BuildSegment([0, p], [0, p+1]);
		BuildSegment([1, p], [1, p+1]);
		BuildRail([0, p-1], [0, p], [1, p+1]);
		BuildRail([1, p-1], [1, p], [0, p+1]);
		BuildSignal([0, p+1], [0, p+2]);
		BuildSignal([1, p+1], [1, p]);
	}
	
	function BuildPlatforms() {
		// template is oriented NW->SE
		local direction;
		if (this.rotation == ROT_0 || this.rotation == ROT_180) {
			direction = AIRail.RAILTRACK_NW_SE;
		} else {
			direction = AIRail.RAILTRACK_NE_SW;
		}
		
		// on the map, location of the station is the topmost tile
		local platform1;
		local platform2;
		if (this.rotation == ROT_0) {
			platform1 = GetTile([0, 0]);
			platform2 = GetTile([1, 0]);
		} else if (this.rotation == ROT_90) {
			platform1 = GetTile([0, platformLength-1]);
			platform2 = GetTile([1, platformLength-1]);
		} else if (this.rotation == ROT_180) {
			platform1 = GetTile([0, platformLength-1]);
			platform2 = GetTile([1, platformLength-1]);
		} else if (this.rotation == ROT_270) {
			platform1 = GetTile([0,0]);
			platform2 = GetTile([1,0]);
		} else {
			throw "invalid rotation";
		}
		
		AIRail.BuildRailStation(platform1, direction, 1, platformLength, AIStation.STATION_NEW);
		CheckError();
		AIRail.BuildRailStation(platform2, direction, 1, platformLength, AIStation.STATION_JOIN_ADJACENT);
		CheckError();
	}
	
	function _tostring() {
		return "BuildTerminusStation";
	}
}

/**
 * Single platform RoRo station.
 */
class BuildRoRoStation extends Builder {
	
	constructor(location) {
		Builder.constructor(location);
	}
	
	function Run() {
		AIRail.BuildRailStation(location, AIRail.RAILTRACK_NE_SW, 1, 3, AIStation.STATION_NEW);
		CheckError();
		AIRail.BuildRailTrack(GetTile(location, [3,0]), AIRail.RAILTRACK_NE_SW);
		CheckError();
		AIRail.BuildRailTrack(GetTile(location, [-1,0]), AIRail.RAILTRACK_NE_SW);
		CheckError();
		BuildSignal([3,0], [4,0]);
		BuildSignal([-1,0], [-2,0]);
	}
	
	function _tostring() {
		return "BuildRoRoStation";
	}
}

class BuildTrack extends Builder {
	
	static SIGNAL_INTERVAL = 3;
	
	a = null;
	b = null;
	c = null;
	d = null;
	ignored = [];
	forwardSignals = null;
	
	constructor(from, to, ignored, forwardSignals) {
		this.a = from[0];
		this.b = from[1];
		this.c = to[0];
		this.d = to[1];
		this.ignored = ignored;
		this.forwardSignals = forwardSignals;
	}
	
	function Run() {
		/*
		AISign.BuildSign(a, "a");
		AISign.BuildSign(b, "b");
		AISign.BuildSign(c, "c");
		AISign.BuildSign(d, "d");
		*/
		
		local path = FindPath(a, b, c, d, ignored);
		if (path) BuildPath(path);
	}
	
	function FindPath(a, b, c, d, ignored) {
		local pathfinder = Rail();
		pathfinder.cost.max_cost = pathfinder.cost.tile * 4 * AIMap.DistanceManhattan(a, d);
		
		pathfinder.cost.diagonal_tile = 200;
		pathfinder.cost.bridge_per_tile = 400;
		pathfinder.InitializePath([[b, a]], [[c, d]], ignored);
		
		Debug("Pathfinding...");
		return pathfinder.FindPath(-1);
	}
	
	function BuildPath(path) {
		Debug("Building...");
		local prev = null;
		local prevprev = null;
		local count = 1;
		while (path != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
					if (AITunnel.GetOtherTunnelEnd(prev) == path.GetTile()) {
						AITunnel.BuildTunnel(AIVehicle.VT_RAIL, prev);
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), prev) + 1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);
						AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, path.GetTile());
					}
					prevprev = prev;
					prev = path.GetTile();
					path = path.GetParent();
				} else {
					AIRail.BuildRail(prevprev, prev, path.GetTile());
					if (count % SIGNAL_INTERVAL == 0) {
						local front = forwardSignals ? path.GetTile() : prevprev;
						AIRail.BuildSignal(prev, front, AIRail.SIGNALTYPE_NORMAL);
					}
					
					count++;
				}
			}
			if (path != null) {
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			}
		}
		
		Debug("Done!");
	}
}
	

class ExtendCrossing extends Builder {

	crossingLocation = null;
	direction = null;
	
	constructor(crossingLocation, direction) {
		this.crossingLocation = crossingLocation;
		this.direction = direction;
	}
	
	function Run() {
		// for now, just expand NE
		local crossingExit = GetTile(crossingLocation, [0,2]);
		local crossingEntrance = GetTile(crossingLocation, [0,1]);
		
		// find next closest town in the expansion direction
		local towns = AITownList();
		towns.Valuate(GetXDistance, crossingExit);
		towns.KeepBelowValue(0);
		towns.Valuate(GetYDistance, crossingExit);
		towns.KeepBetweenValue(-50, 50);
		
		for (local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
			AISign.BuildSign(AITown.GetLocation(town), "" + GetXDistance(town, crossingExit));
		}
		
		towns.Valuate(AITown.GetDistanceManhattanToTile, crossingExit);
		towns.KeepBottom(1);
		local town = towns.Begin();
		
		// TODO: build crossing if it's off to the sides enough
		
		Debug("Select site for station");
		local sign = FindSign("x");
		local stationTile = AISign.GetLocation(sign);
		AISign.RemoveSign(sign);
		BuildStation(stationTile).Run();
		
		// TODO: build the shorter track first
		local stationExit = GetStationExit(stationTile);
		BuildTrack(stationExit, GetTile(stationExit, [0,1]), GetTile(crossingEntrance, [-1,0]), crossingEntrance).Run();
		
		local stationEntrance = GetStationEntrance(stationTile);
		BuildTrack(crossingExit, GetTile(crossingExit, [-1,0]), GetTile(stationEntrance, [0,1]), stationEntrance).Run(); 
	}
	
	function GetXDistance(town, tile) {
		return AIMap.GetTileX(AITown.GetLocation(town)) - AIMap.GetTileX(tile);
	}
	
	function GetYDistance(town, tile) {
		return AIMap.GetTileY(AITown.GetLocation(town)) - AIMap.GetTileY(tile);
	}
	
	function GetStationEntrance(stationTile) {
		// use the fact that all stations are currently facing SE
		return GetTile(stationTile, [0,4]);
	}
	
	function GetStationExit(stationTile) {
		// use the fact that all stations are currently facing SE
		return GetTile(stationTile, [1,4]);
	}
		
}



class LevelTerrain extends Builder {
	
	location = null;
	from = null;
	to = null;
	
	constructor(location, rotation, from, to) {
		Builder.constructor(location, rotation);
		this.from = from;
		this.to = to;
	}
	
	function Run() {
		// TODO: this levels the area between the north corners of the resulting tiles
		// so due to rotation, we may be one tile short
		if (!AITile.LevelTiles(GetTile(from), GetTile(to))) {
			CheckError();
		}
	}
	
	function _tostring() {
		return "LevelTerrain";
	}
	
}
