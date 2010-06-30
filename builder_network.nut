class BuildNewNetwork extends Task {
	
	static MAX_ATTEMPTS = 50;
	network = null;
	
	constructor(minDistance = MIN_DISTANCE, maxDistance = MAX_DISTANCE) {
		this.network = Network(AIRailTypeList().Begin(), RAIL_STATION_PLATFORM_LENGTH, minDistance, maxDistance);
	}
	
	function Run() {
		local tile;
		local count = 0;
		
		while (true) {
			tile = RandomTile();
			if (AIMap.IsValidTile(tile) &&
				AITile.IsBuildableRectangle(
					tile - AIMap.GetTileIndex(Crossing.WIDTH, Crossing.WIDTH),
					Crossing.WIDTH*3, Crossing.WIDTH*3) &&
				EstimateNetworkStationCount(tile) >= 3) break;
			
			count++;
			if (count >= MAX_ATTEMPTS) {
				Warning("Tried " + count + " locations to start a new network, map may be full. Trying again tomorrow...");
				throw TaskRetryException(TICKS_PER_DAY);
			} else {
				AIController.Sleep(1);
			}
		}
		
		AIRail.SetCurrentRailType(network.railType);
		tasks.insert(1, TaskList(this, [
			LevelTerrain(tile, Rotation.ROT_0, [1, 1], [Crossing.WIDTH-2, Crossing.WIDTH-2]),
			BuildCrossing(tile, network)
		]));
	}
	
	function _tostring() {
		return "BuildNewNetwork";
	}
	
	function EstimateNetworkStationCount(tile) {
		local stationCount = 0;
		local estimationNetwork = Network(network.railType, RAIL_STATION_PLATFORM_LENGTH, network.minDistance, network.maxDistance);
		foreach (direction in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
			stationCount += EstimateCrossing(tile, direction, estimationNetwork);
		}
		
		Debug("Estimated stations for crossing at " + TileToString(tile) + ": " + stationCount);
		return stationCount;
	}
	
	function EstimateCrossing(tile, direction, estimationNetwork) {
		// for now, ignore potential gains from newly built crossings
		local extender = ExtendCrossing(tile, direction, estimationNetwork);
		local towns = extender.FindTowns();
		local town = null;
		local stationTile = null;
		for (town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
			stationTile = FindStationSite(town, BuildTerminusStation.StationRotationForDirection(direction), tile);
			if (stationTile) {
				return 1;
			}
		}
		
		return 0;
	}
}


class BuildCrossing extends Builder {
	
	static counter = Counter()
	network = null;
	extenders = null;
	
	constructor(location, network) {
		Builder.constructor(location);
		this.network = network;
		
		// expand in opposite directions first, to maximize potential gains
		this.extenders = [
			ExtendCrossing(location, Direction.NE, network),
			ExtendCrossing(location, Direction.SW, network),
			ExtendCrossing(location, Direction.NW, network),
			ExtendCrossing(location, Direction.SE, network),
		]
	}
	
	function Run() {
		SetConstructionSign(location, this);
		
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
		
		// long inner diagonals
		//BuildRail([0,1], [1,1], [2,3]);
		//BuildRail([0,2], [1,2], [2,0]);
		//BuildRail([1,3], [1,2], [3,1]);
		//BuildRail([3,2], [2,2], [1,0]);
		
		// inner diagonals (clockwise)
		BuildRail([2,1], [1,1], [1,2]);
		BuildRail([1,1], [1,2], [2,2]);
		BuildRail([2,1], [2,2], [1,2]);
		BuildRail([1,1], [2,1], [2,2]);
		
		// signals (clockwise)
		// initially, all signals face outwards to block trains off from unfinished tracks
		// after an exit is connected, we open it up by either flipping or removing the signal
		local type = AIRail.SIGNALTYPE_PBS_ONEWAY;
		BuildSignal([0,1], [-1, 1], type);
		BuildSignal([0,2], [-1, 2], type);
		BuildSignal([1,3], [ 1, 4], type);
		BuildSignal([2,3], [ 2, 4], type);
		BuildSignal([3,2], [ 4, 2], type);
		BuildSignal([3,1], [ 4, 1], type);
		BuildSignal([2,0], [ 2,-1], type);
		BuildSignal([1,0], [ 1,-1], type);
		
		tasks.extend(extenders);
		
		if (!HaveHQ()) {
			tasks.append(BuildHQ(location));
		}
	}
	
	function _tostring() {
		return "BuildCrossing " + TileToString(location);
	}
	
	function Failed() {
		// cancel ExtendCrossing tasks we created
		foreach (task in extenders) {
			task.Cancel();
		}

		// one exit should have a waypoint which we need to demolish
		Demolish([0,2])
		Demolish([2,3])
		Demolish([3,1])
		Demolish([1,0])
		
		// four segments of track
		RemoveSegment([0,1], [3,1]);
		RemoveSegment([0,2], [3,2]);
		RemoveSegment([1,0], [1,3]);
		RemoveSegment([2,0], [2,3]);
		
		// outer diagonals (clockwise)
		RemoveRail([1,0], [1,1], [0,1]);
		RemoveRail([0,2], [1,2], [1,3]);
		RemoveRail([3,2], [2,2], [2,3]);
		RemoveRail([2,0], [2,1], [3,1]);
		
		// long inner diagonals
		//RemoveRail([0,1], [1,1], [2,3]);
		//RemoveRail([0,2], [1,2], [2,0]);
		//RemoveRail([1,3], [1,2], [3,1]);
		//RemoveRail([3,2], [2,2], [1,0]);
		
		// inner diagonals (clockwise)
		RemoveRail([2,1], [1,1], [1,2]);
		RemoveRail([1,1], [1,2], [2,2]);
		RemoveRail([2,1], [2,2], [1,2]);
		RemoveRail([1,1], [2,1], [2,2]);
	}
	
}

class ConnectStation extends TaskList {
	
	crossingTile = null;
	direction = null;
	stationTile = null;
	network = null;
	
	constructor(crossingTile, direction, stationTile, network) {
		TaskList.constructor(this, null);
		this.crossingTile = crossingTile;
		this.direction = direction;
		this.stationTile = stationTile;
		this.network = network;
	}
	
	function Run() {
		SetConstructionSign(crossingTile, this);
		
		local crossing = Crossing(crossingTile);
		
		if (!subtasks) {
			subtasks = [];
			local station = TerminusStation.AtLocation(stationTile, RAIL_STATION_PLATFORM_LENGTH);
			
			// if we ran these subtasks as a task list, we can't signal failure to our parent task list
			// so, we run them inline, making sure we can be restarted
			// TODO: clean this up?
			
			local reserved = station.GetReservedEntranceSpace();
			reserved.extend(crossing.GetReservedExitSpace(direction));
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != direction) {
					reserved.extend(crossing.GetReservedEntranceSpace(d));
					reserved.extend(crossing.GetReservedExitSpace(d));
				}
			}
				
			subtasks.append(BuildTrack(station.GetExit(), crossing.GetEntrance(direction), reserved, SignalMode.FORWARD, network));
			
			// we don't have to reserve space for the path we just connected 
			//local reserved = station.GetReservedExitSpace();
			//reserved.extend(crossing.GetReservedEntranceSpace(direction));
			local reserved = [];
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != direction) {
					reserved.extend(crossing.GetReservedEntranceSpace(d));
					reserved.extend(crossing.GetReservedExitSpace(d));
				}
			}
			
			subtasks.append(BuildTrack(Swap(station.GetEntrance()), Swap(crossing.GetExit(direction)), reserved, SignalMode.BACKWARD, network));
		}
		
		RunSubtasks();
			
		// open up the exit by removing the signal
		local exit = crossing.GetExit(direction);
		AIRail.RemoveSignal(exit[0], exit[1]);
	}
	
	function _tostring() {
		local station = AIStation.GetStationID(stationTile);
		local name = AIStation.IsValidStation(station) ? AIStation.GetName(station) : "unnamed";
		return "ConnectStation " + name + " to " + Crossing(crossingTile) + " " + DirectionName(direction);
	}
}

class ConnectCrossing extends TaskList {
	
	fromCrossingTile = null;
	fromDirection = null;
	toCrossingTile = null;
	toDirection = null;
	network = null;
	
	constructor(fromCrossingTile, fromDirection, toCrossingTile, toDirection, network) {
		TaskList.constructor(this, null)
		this.fromCrossingTile = fromCrossingTile;
		this.fromDirection = fromDirection;
		this.toCrossingTile = toCrossingTile;
		this.toDirection = toDirection;
		this.network = network;
	}
	
	function Run() {
		SetConstructionSign(fromCrossingTile, this);
		
		local fromCrossing = Crossing(fromCrossingTile);
		local toCrossing = Crossing(toCrossingTile);
		
		if (!subtasks) {
			subtasks = [];
		
			local reserved = toCrossing.GetReservedEntranceSpace(toDirection);
			reserved.extend(fromCrossing.GetReservedExitSpace(fromDirection));
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != fromDirection) {
					reserved.extend(fromCrossing.GetReservedEntranceSpace(d));
					reserved.extend(fromCrossing.GetReservedExitSpace(d));
				}
				
				if (d != toDirection) {
					reserved.extend(toCrossing.GetReservedEntranceSpace(d));
					reserved.extend(toCrossing.GetReservedExitSpace(d));
				}
			}
			
			subtasks.append(BuildTrack(toCrossing.GetExit(toDirection), fromCrossing.GetEntrance(fromDirection), reserved, SignalMode.FORWARD, network));
		
			//local reserved = toCrossing.GetReservedExitSpace(toDirection);
			//reserved.extend(fromCrossing.GetReservedEntranceSpace(fromDirection));
			local reserved = [];
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != fromDirection) {
					reserved.extend(fromCrossing.GetReservedEntranceSpace(d));
					reserved.extend(fromCrossing.GetReservedExitSpace(d));
				}
				
				if (d != toDirection) {
					reserved.extend(toCrossing.GetReservedEntranceSpace(d));
					reserved.extend(toCrossing.GetReservedExitSpace(d));
				}
			}
			
			subtasks.append(BuildTrack(Swap(toCrossing.GetEntrance(toDirection)), Swap(fromCrossing.GetExit(fromDirection)), reserved, SignalMode.BACKWARD, network));
		}
		
		RunSubtasks();
		
		// open up both crossings' exits
		local exit = fromCrossing.GetExit(fromDirection);
		AIRail.RemoveSignal(exit[0], exit[1]);
		if (fromCrossing.GetName() == "unnamed junction" && AIController.GetSetting("JunctionNames")) {
			BuildWaypoint(exit[0]);
		}
		
		exit = toCrossing.GetExit(toDirection);
		AIRail.RemoveSignal(exit[0], exit[1]);
		if (toCrossing.GetName() == "unnamed junction" && AIController.GetSetting("JunctionNames")) {
			BuildWaypoint(exit[0]);
		}
	}
	
	function BuildWaypoint(tile) {
		local town = AITile.GetClosestTown(tile);
		AIRail.BuildRailWaypoint(tile);
		local waypoint = AIWaypoint.GetWaypointID(tile);
		local suffixes = ["Junction", "Crossing", "Point", "Union", "Switch", "Cross", "Points"]
		foreach (suffix in suffixes) {
			if (AIWaypoint.SetName(waypoint, AITown.GetName(town) + " " + suffix)) {
				break;
			}
		}
	}
	
	function _tostring() {
		return "ConnectCrossing " + Crossing(fromCrossingTile) + " " + DirectionName(fromDirection) + " to " + Crossing(toCrossingTile);
	}
}

class ExtendCrossing extends TaskList {

	static MIN_TOWN_POPULATION = 200;
	crossing = null;
	direction = null;
	network = null;
	cancelled = null;
	town = null;
	stationTile = null;
	
	constructor(crossing, direction, network) {
		TaskList.constructor(this, null);
		this.crossing = crossing;
		this.direction = direction;
		this.network = network;
		this.cancelled = false;
		this.town = null;
		this.stationTile = null;
	}
	
	function _tostring() {
		return "ExtendCrossing " + Crossing(crossing) + " " + DirectionName(direction);
	}
	
	function Cancel() {
		this.cancelled = true;
	}
	
	function Run() {
		// we can be cancelled if BuildCrossing failed
		if (cancelled) return;
		
		// see if we've not already built this direction
		// if we have subtasks but we do find rails, assume we're still building
		local exit = Crossing(crossing).GetExit(direction);
		if (!subtasks && AIRail.IsRailTile(exit[1])) {
			return;
		}
		
		if (!subtasks) {
			SetConstructionSign(crossing, this);
			local towns = FindTowns();
			local stationRotation = BuildTerminusStation.StationRotationForDirection(direction);
			
			town = null;
			stationTile = null;
			for (town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
				stationTile = FindStationSite(town, stationRotation, crossing);
				if (stationTile) break;
			}
			
			if (!stationTile) {
				throw TaskFailedException("no towns " + DirectionName(direction) + " of " + Crossing(crossing) + " where we can build a station");
			}
			
			local crossingTile = FindCrossingSite(stationTile);
			if (crossingTile) {
				local crossingEntranceDirection = InverseDirection(direction);
				local crossingExitDirection = CrossingExitDirection(crossingTile, stationTile);
				
				subtasks = [
					LevelTerrain(stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2], true),
					AppeaseLocalAuthority(town),
					BuildTerminusStation(stationTile, direction, network, town),
					AppeaseLocalAuthority(town),
					BuildBusStations(stationTile, town),
					LevelTerrain(crossingTile, Rotation.ROT_0, [1, 1], [Crossing.WIDTH-2, Crossing.WIDTH-2]),
					BuildCrossing(crossingTile, network),
					ConnectCrossing(crossing, direction, crossingTile, crossingEntranceDirection, network),
					ConnectStation(crossingTile, crossingExitDirection, stationTile, network),
					BuildTrains(stationTile, network, PAX),
				];
			} else {
				subtasks = [
					LevelTerrain(stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2], true),
					AppeaseLocalAuthority(town),
					BuildTerminusStation(stationTile, direction, network, town),
					AppeaseLocalAuthority(town),
					BuildBusStations(stationTile, town),
					ConnectStation(crossing, direction, stationTile, network),
					BuildTrains(stationTile, network, PAX),
				];
			}
			
			// build an extra train for the second station in a network
			// at this point, that means we only have one station in the network
			if (network.stations.len() == 1) {
				local firstStation = AIStation.GetLocation(network.stations[0]);
				subtasks.append(BuildTrains(firstStation, network, PAX));
			}
		}
		
		RunSubtasks();
		tasks.insert(1, BuildBusService(stationTile, town));
	}
	
	function CrossingExitDirection(crossingTile, stationTile) {
		local dx = AIMap.GetTileX(stationTile) - AIMap.GetTileX(crossingTile);
		local dy = AIMap.GetTileY(stationTile) - AIMap.GetTileY(crossingTile);
		
		// leave the new crossing in a direction perpendicular to the one we came in through
		switch (direction) {
			case Direction.NE: return dy > 0 ? Direction.SE : Direction.NW;
			case Direction.SE: return dx > 0 ? Direction.SW : Direction.NE;
			case Direction.SW: return dy > 0 ? Direction.SE : Direction.NW;
			case Direction.NW: return dx > 0 ? Direction.SW : Direction.NE;
			default: throw "invalid direction";
		}
	}
	
	/*
	 * Find towns in the expansion direction that don't already have a station.
	 */
	function FindTowns() {
		local towns = AIList();
		towns.AddList(AITownList());
		
		// filter out the tiny ones
		towns.Valuate(AITown.GetPopulation);
		towns.KeepAboveValue(MIN_TOWN_POPULATION);
		
		local stations = AIStationList(AIStation.STATION_TRAIN);
		for (local station = stations.Begin(); stations.HasNext(); station = stations.Next()) {
			towns.RemoveItem(AIStation.GetNearestTown(station));
		}
		
		switch (direction) {
			case Direction.NE:
				// negative X
				FilterTowns(towns, crossing, GetXDistance, false, GetYDistance);
				break;
				
			case Direction.SE:
				// positive Y
				FilterTowns(towns, crossing, GetYDistance, true, GetXDistance);
				break;
				
			case Direction.SW:
				// positive X
				FilterTowns(towns, crossing, GetXDistance, true, GetYDistance);
				break;
				
			case Direction.NW:
				// negative Y
				FilterTowns(towns, crossing, GetYDistance, false, GetXDistance);
				break;
			
			default: throw "invalid direction";
		}
		
		towns.Valuate(AITown.GetDistanceManhattanToTile, crossing);
		towns.Sort(AIList.SORT_BY_VALUE, true);
		return towns;
	}
	
	function FilterTowns(towns, location, lengthValuator, positive, widthValuator) {
		// remove that are too close or too far
		towns.Valuate(lengthValuator, location);
		if (positive) {
			towns.RemoveBelowValue(network.minDistance);
			towns.RemoveAboveValue(network.maxDistance);
		} else {
			towns.RemoveAboveValue(-network.minDistance);
			towns.RemoveBelowValue(-network.maxDistance);
		}
		
		// remove towns too far off to the side
		towns.Valuate(widthValuator, location);
		towns.KeepBetweenValue(-network.maxDistance/2, network.maxDistance/2);
	}
	
	function GetXDistance(town, tile) {
		return AIMap.GetTileX(AITown.GetLocation(town)) - AIMap.GetTileX(tile);
	}
	
	function GetYDistance(town, tile) {
		return AIMap.GetTileY(AITown.GetLocation(town)) - AIMap.GetTileY(tile);
	}
	
	function FindCrossingSite(stationTile) {
		local dx = AIMap.GetTileX(stationTile) - AIMap.GetTileX(crossing);
		local dy = AIMap.GetTileY(stationTile) - AIMap.GetTileY(crossing);
		if (abs(dx) < 2*Crossing.WIDTH || abs(dy) < 2*Crossing.WIDTH) return null;
		
		local centerTile = crossing;
		if (direction == Direction.NE || direction == Direction.SW) {
			centerTile += AIMap.GetTileIndex(dx - Sign(dx) * (RAIL_STATION_LENGTH + 1), 0);
		} else {
			centerTile += AIMap.GetTileIndex(0, dy - Sign(dy) * (RAIL_STATION_LENGTH + 1));
		}
		
		// find a buildable area closest to ideal tile
		local tiles = AITileList();
		SafeAddRectangle(tiles, centerTile, Crossing.WIDTH);
		tiles.Valuate(IsBuildableRectangle, Rotation.ROT_0, [-2, -2], [Crossing.WIDTH + 2, Crossing.WIDTH + 2], false);
		tiles.KeepValue(1);
		tiles.Valuate(AIMap.DistanceManhattan, centerTile);
		tiles.KeepBottom(1);
		return tiles.IsEmpty() ? null : tiles.Begin();
	}
	
	function SubtaskFailed() {
		// either we didn't find a town, or one of our subtasks failed
		//tasks.push(ExtendCrossingCleanup(crossing, direction));
		ExtendCrossingCleanup(crossing, direction).Run();
	}
}

class ExtendCrossingCleanup extends Builder {
	
	direction = null;
	
	constructor(location, direction) {
		Builder.constructor(location, Rotation.ROT_0);
		this.direction = direction;
	}
	
	function _tostring() {
		return "Cleanup " + Crossing(location) + " " + DirectionName(direction);
	}
	
	function Run() {
		local entrance = Crossing(location).GetEntrance(direction);
		local exit = Crossing(location).GetExit(direction);
		
		// use the NE direction as a template and derive the others
		// by rotation and offset
		local rotation;
		local offset;
		
		switch (direction) {
			case Direction.NE:
				rotation = Rotation.ROT_0;
				offset = [0,0];
				break;
			
			case Direction.SE:
				rotation = Rotation.ROT_270;
				offset = [0,3];
				break;
				
			case Direction.SW:
				rotation = Rotation.ROT_180;
				offset = [3,3];
				break;
				
			case Direction.NW:
				rotation = Rotation.ROT_90;
				offset = [3,0];
				break;
		}
		
		// move coordinate system
		SetLocalCoordinateSystem(GetTile(offset), rotation);
		
		// the exit might have a waypoint
		Demolish([0,2]);
		
		RemoveRail([-1,1], [0,1], [1,1]);
		RemoveRail([-1,2], [0,2], [1,2]);
		
		RemoveRail([0,1], [1,1], [1,0]);
		RemoveRail([0,1], [1,1], [2,1]);
		
		RemoveRail([0,2], [1,2], [2,2]);
		RemoveRail([0,2], [1,2], [1,3]);
		
		RemoveRail([2,2], [2,1], [1,1]);
		RemoveRail([2,1], [2,2], [1,2]);
		
		// we can remove more bits if another direction is already gone
		if (!HasRail([1,3])) {
			RemoveRail([1,1], [2,1], [3,1]);
			RemoveRail([2,0], [2,1], [2,2]);
			RemoveRail([2,1], [2,2], [2,3]);
		}
		
		if (!HasRail([1,0])) {
			RemoveRail([1,2], [2,2], [3,2]);
			RemoveRail([2,0], [2,1], [2,2]);
			RemoveRail([2,1], [2,2], [2,3]);
		}
	}
	
	function HasRail(tileCoords) {
		return AIRail.IsRailTile(GetTile(tileCoords));
	}
}
