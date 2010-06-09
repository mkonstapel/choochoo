/**
 * Single platform terminus station.
 */
class BuildCargoStation extends Builder {
	
	network = null;
	industry = null;
	platformLength = null;
	
	constructor(location, direction, network, industry, platformLength) {
		Builder.constructor(location, StationRotationForDirection(direction));
		this.network = network;
		this.industry = industry;
		this.platformLength = platformLength;
	}
	
	function Run() {
		MoveConstructionSign(location, this);
		
		BuildPlatform();
		local p = platformLength;
		BuildSegment([0, p], [0, p+1]);
		BuildDepot([1,p], [0,p]);
		BuildRail([1, p], [0, p], [0, p-1]);
		BuildRail([1, p], [0, p], [0, p+1]);
		network.depots.append(GetTile([1,p]));
		network.stations.append(AIStation.GetStationID(location));
	}
	
	function StationRotationForDirection(direction) {
		switch (direction) {
			case Direction.NE: return Rotation.ROT_270;
			case Direction.SE: return Rotation.ROT_180;
			case Direction.SW: return Rotation.ROT_90;
			case Direction.NW: return Rotation.ROT_0;
			default: throw "invalid direction";
		}
	}
	
	function Failed() {
		local station = AIStation.GetStationID(location);
		foreach (index, entry in network.stations) {
			if (entry == station) {
				network.stations.remove(index);
				break;
			}
		}
		
		foreach (y in Range(0, platformLength+2)) {
			Demolish([0,y]);
		}
		
		Demolish([1, platformLength]);	// depot
	}
	
	/**
	 * Build station platform. Returns stationID.
	 */
	function BuildPlatform() {
		// template is oriented NW->SE
		local direction;
		if (this.rotation == Rotation.ROT_0 || this.rotation == Rotation.ROT_180) {
			direction = AIRail.RAILTRACK_NW_SE;
		} else {
			direction = AIRail.RAILTRACK_NE_SW;
		}
		
		// on the map, location of the station is the topmost tile
		local platform;
		if (this.rotation == Rotation.ROT_0) {
			platform = GetTile([0, 0]);
		} else if (this.rotation == Rotation.ROT_90) {
			platform = GetTile([0, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_180) {
			platform = GetTile([0, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_270) {
			platform = GetTile([0,0]);
		} else {
			throw "invalid rotation";
		}
		
		AIRail.BuildRailStation(platform, direction, 1, platformLength, AIStation.STATION_NEW);
		CheckError();
		return AIStation.GetStationID(platform);
	}
	
	function _tostring() {
		return "BuildCargoStation at " + AIIndustry.GetName(industry);
	}
}

/**
 * 2-platform terminus station.
 */
class BuildTerminusStation extends Builder {
	
	network = null;
	town = null;
	platformLength = null;
	builtPlatform1 = null;
	builtPlatform2 = null;
	doubleTrack = null;
	
	constructor(location, direction, network, town, doubleTrack = true, platformLength = RAIL_STATION_PLATFORM_LENGTH) {
		Builder.constructor(location, StationRotationForDirection(direction));
		this.network = network;
		this.town = town;
		this.platformLength = platformLength;
		this.builtPlatform1 = false;
		this.builtPlatform2 = false;
		this.doubleTrack = doubleTrack;
	}
	
	function Run() {
		MoveConstructionSign(location, this);
		
		BuildPlatforms();
		local p = platformLength;
		BuildSegment([0, p], [0, p+1]);
		if (doubleTrack) BuildSegment([1, p], [1, p+1]);
		BuildRail([1, p-1], [1, p], [0, p+1]);
		if (doubleTrack) BuildRail([0, p-1], [0, p], [1, p+1]);
		
		BuildDepot([2,p], [1,p]);
		BuildRail([2, p], [1, p], [0, p]);
		BuildRail([2, p], [1, p], [1, p-1]);
		BuildRail([1, p], [0, p], [0, p-1]);
		if (doubleTrack) BuildRail([2, p], [1, p], [1, p+1]);
		network.depots.append(GetTile([2,p]));
		
		BuildSignal([0, p+1], [0, p+2], AIRail.SIGNALTYPE_PBS);
		BuildSignal([1, p+1], [1, p],   AIRail.SIGNALTYPE_PBS);
		network.stations.append(AIStation.GetStationID(location));
	}
	
	function StationRotationForDirection(direction) {
		switch (direction) {
			case Direction.NE: return Rotation.ROT_270;
			case Direction.SE: return Rotation.ROT_180;
			case Direction.SW: return Rotation.ROT_90;
			case Direction.NW: return Rotation.ROT_0;
			default: throw "invalid direction";
		}
	}
	
	function Failed() {
		local station = AIStation.GetStationID(location);
		foreach (index, entry in network.stations) {
			if (entry == station) {
				network.stations.remove(index);
				break;
			}
		}
		
		foreach (x in Range(0, 2)) {
			foreach (y in Range(0, platformLength+2)) {
				Demolish([x,y]);
			}
		}
		
		Demolish([2, platformLength]);	// depot
	}
	
	/**
	 * Build station platforms. Returns stationID.
	 */
	function BuildPlatforms() {
		// template is oriented NW->SE
		local direction;
		if (this.rotation == Rotation.ROT_0 || this.rotation == Rotation.ROT_180) {
			direction = AIRail.RAILTRACK_NW_SE;
		} else {
			direction = AIRail.RAILTRACK_NE_SW;
		}
		
		// on the map, location of the station is the topmost tile
		local platform1;
		local platform2;
		if (this.rotation == Rotation.ROT_0) {
			platform1 = GetTile([0, 0]);
			platform2 = GetTile([1, 0]);
		} else if (this.rotation == Rotation.ROT_90) {
			platform1 = GetTile([0, platformLength-1]);
			platform2 = GetTile([1, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_180) {
			platform1 = GetTile([0, platformLength-1]);
			platform2 = GetTile([1, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_270) {
			platform1 = GetTile([0,0]);
			platform2 = GetTile([1,0]);
		} else {
			throw "invalid rotation";
		}
		
		if (!builtPlatform1) {
			AIRail.BuildRailStation(platform1, direction, 1, platformLength, AIStation.STATION_NEW);
			CheckError();
			builtPlatform1 = true;
		}
		
		if (!builtPlatform2) {
			AIRail.BuildRailStation(platform2, direction, 1, platformLength, AIStation.GetStationID(platform1));
			CheckError();
			builtPlatform2 = true;
		}
		
		return AIStation.GetStationID(platform1);
	}
	
	function _tostring() {
		return "BuildTerminusStation at " + AITown.GetName(town);
	}
}

/**
 * Increase the capture area of a train station by joining bus stations to it.
 */
class BuildBusStations extends Builder {

	stationTile = null;
	town = null;
	stations = null;
		
	constructor(stationTile, town) {
		this.stationTile = stationTile;
		this.town = town;
		this.stations = [];
	}
	
	function _tostring() {
		return "BuildBusStations";
	}
	
	function Run() {
		// consider the area between the station and the center of town
		local area = AITileList();
		area.AddRectangle(stationTile, AITown.GetLocation(town));
		SafeAddRectangle(area, AITown.GetLocation(town), 2);
		
		area.Valuate(AIRoad.IsRoadTile);
		area.KeepValue(1);
		
		area.Valuate(AIMap.DistanceManhattan, stationTile);
		area.Sort(AIList.SORT_BY_VALUE, true);
		
		// try all road tiles; if a station is built, don't build another in its vicinity
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			if (BuildStationAt(tile)) {
				stations.append(tile);
				area.RemoveRectangle(tile - AIMap.GetTileIndex(2, 2), tile + AIMap.GetTileIndex(2, 2));
			}
		}
	}
	
	function BuildStationAt(tile) {
		return BuildStation(tile, true) || BuildStation(tile, false);
	}
	
	function BuildStation(tile, facing) {
		local front = tile + (facing ? AIMap.GetTileIndex(0,1) : AIMap.GetTileIndex(1,0));
		return AIRoad.BuildDriveThroughRoadStation(tile, front, AIRoad.ROADVEHTYPE_BUS, AIStation.GetStationID(stationTile));
	}
	
	function Failed() {
		foreach (tile in stations) {
			AIRoad.RemoveRoadStation(tile);
		}
	}
}