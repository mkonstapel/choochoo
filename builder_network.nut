/*
 * Find towns in the expansion direction that don't already have a station.
 */
function FindTowns(fromTile, direction, minPopulation, minDistance, maxDistance, maxWidth, ignoreBranchStations) {
	local towns = AIList();
	towns.AddList(AITownList());
	
	// filter out the tiny ones
	towns.Valuate(AITown.GetPopulation);
	towns.KeepAboveValue(minPopulation);
	
	local stations = AIStationList(AIStation.STATION_TRAIN);
	for (local station = stations.Begin(); stations.HasNext(); station = stations.Next()) {
		if (ignoreBranchStations && IsBranchLineStation(station)) {
			// a town can still get a mainline station if it already has a branch station
		} else {
			// any station counts, towns don't get multiple branch stations
			towns.RemoveItem(AIStation.GetNearestTown(station));
		}
	}
	
	switch (direction) {
		case Direction.NE:
			// negative X
			FilterTowns(towns, fromTile, GetXDistance, false, GetYDistance, minDistance, maxDistance, maxWidth);
			break;
			
		case Direction.SE:
			// positive Y
			FilterTowns(towns, fromTile, GetYDistance, true, GetXDistance, minDistance, maxDistance, maxWidth);
			break;
			
		case Direction.SW:
			// positive X
			FilterTowns(towns, fromTile, GetXDistance, true, GetYDistance, minDistance, maxDistance, maxWidth);
			break;
			
		case Direction.NW:
			// negative Y
			FilterTowns(towns, fromTile, GetYDistance, false, GetXDistance, minDistance, maxDistance, maxWidth);
			break;
		
		default: throw "invalid direction";
	}
	
	return towns;
}

function FilterTowns(towns, location, lengthValuator, positive, widthValuator, minDistance, maxDistance, maxWidth) {
	// remove that are too close or too far
	towns.Valuate(lengthValuator, location);
	if (positive) {
		towns.RemoveBelowValue(minDistance);
		towns.RemoveAboveValue(maxDistance);
	} else {
		towns.RemoveAboveValue(-minDistance);
		towns.RemoveBelowValue(-maxDistance);
	}
	
	// remove towns too far off to the side
	towns.Valuate(widthValuator, location);
	towns.KeepBetweenValue(-maxWidth, maxWidth);
}

function GetXDistance(town, tile) {
	return AIMap.GetTileX(AITown.GetLocation(town)) - AIMap.GetTileX(tile);
}

function GetYDistance(town, tile) {
	return AIMap.GetTileY(AITown.GetLocation(town)) - AIMap.GetTileY(tile);
}

class BuildNewNetwork extends Task {
	
	static MAX_ATTEMPTS = 50;
	network = null;
	
	constructor(parentTask, minDistance = MIN_DISTANCE, maxDistance = MAX_DISTANCE) {
		Task.constructor(parentTask);
		
		// TODO SelectRailType(PAX), choose fastest?
		this.network = Network(AIRailTypeList().Begin(), IsRightHandTraffic(), 3, minDistance, maxDistance);
	}
	
	function Run() {
		local tile;
		local count = 0;
		
		if (!subtasks) {
			while (true) {
				tile = RandomTile();
				SetConstructionSign(tile, this);
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
			subtasks = [
				LevelTerrain(this, tile, Rotation.ROT_0, [1, 1], [Crossing.WIDTH-2, Crossing.WIDTH-2], false),
				BuildCrossing(this, tile, network)
			];
		}
		
		RunSubtasks();

		// TOOD maybe preferentially expand in the direction farthest from the edge of the map?
		tasks.append(ExtendCrossing(null, tile, Direction.NE, network));
		tasks.append(ExtendCrossing(null, tile, Direction.SW, network));
		tasks.append(ExtendCrossing(null, tile, Direction.NW, network));
		tasks.append(ExtendCrossing(null, tile, Direction.SE, network));
	}
	
	function _tostring() {
		return "BuildNewNetwork";
	}
	
	function EstimateNetworkStationCount(tile) {
		local stationCount = 0;
		local estimationNetwork = Network(network.railType, network.rightSide, RAIL_STATION_PLATFORM_LENGTH, network.minDistance, network.maxDistance);
		foreach (direction in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
			stationCount += EstimateCrossing(tile, direction, estimationNetwork);
		}
		
		Debug("Estimated stations for crossing at " + TileToString(tile) + ": " + stationCount);
		return stationCount;
	}
	
	function EstimateCrossing(tile, direction, estimationNetwork) {
		// for now, ignore potential gains from newly built crossings
		local towns = FindTowns(tile, direction, ExtendCrossing.MIN_TOWN_POPULATION, estimationNetwork.minDistance, estimationNetwork.maxDistance, estimationNetwork.maxDistance/2, true);
		local town = null;
		local stationTile = null;
		for (town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
			stationTile = FindMainlineStationSite(town, StationRotationForDirection(direction), tile);
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
	
	constructor(parentTask, location, network) {
		Builder.constructor(parentTask, location);
		this.network = network;
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

		if (!HaveHQ()) {
			tasks.append(BuildHQ(null, location));
		}
	}
	
	function _tostring() {
		return "BuildCrossing " + TileToString(location);
	}
	
	function Failed() {
		Task.Failed();
		
		// one exit should have a waypoint which we need to demolish
		if (network.rightSide) {
			Demolish([0,2])
			Demolish([2,3])
			Demolish([3,1])
			Demolish([1,0])
		} else {
			Demolish([0,1])
			Demolish([1,3])
			Demolish([3,2])
			Demolish([2,0])
		}

		
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

class ConnectStation extends Task {
	
	crossingTile = null;
	direction = null;
	stationTile = null;
	network = null;
	
	constructor(parentTask, crossingTile, direction, stationTile, network) {
		Task.constructor(parentTask);
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
			
			local reserved = network.rightSide ? station.GetReservedEntranceSpace() : station.GetReservedExitSpace();
			reserved.extend(network.rightSide ? crossing.GetReservedExitSpace(direction) : crossing.GetReservedEntranceSpace(direction));
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != direction) {
					reserved.extend(crossing.GetReservedEntranceSpace(d));
					reserved.extend(crossing.GetReservedExitSpace(d));
				}
			}
			
			// because the pathfinder returns a path as a linked list from the
			// goal back to the start, we build "in reverse", and because we
			// want the first signal block (from the station or junction
			// exit) to be large enough, we always want to start building
			// from that end so we actually pathfind in reverse (entrance to
			// exit) and therefore, build forward (exit to entrance)
			local from, to;
			if (network.rightSide) {
				from = Swap(crossing.GetEntrance(direction));
				to = Swap(station.GetExit());
			} else {
				from = crossing.GetExit(direction);
				to = station.GetEntrance();
			}

			local first = BuildTrack(this,
				from, to,
				reserved, SignalMode.BACKWARD, network);
			
			subtasks.append(first);
			
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
			
			if (network.rightSide) {
				from = Swap(station.GetEntrance());
				to = Swap(crossing.GetExit(direction));
			} else {
				from = station.GetExit();
				to = crossing.GetEntrance(direction);
			}
			subtasks.append(BuildTrack(this,
				from, to,
				reserved, SignalMode.BACKWARD, network,
				BuildTrack.FOLLOW, first));
		}
		
		RunSubtasks();
			
		// open up the exit by removing the signal
		local exit = network.rightSide ? crossing.GetExit(direction) : Swap(crossing.GetEntrance(direction));
		AIRail.RemoveSignal(exit[0], exit[1]);
		
		if (StartsWith(crossing.GetName(), "unnamed") && AIController.GetSetting("JunctionNames")) {
			BuildWaypoint(exit[0]);
		}
	}
	
	function BuildWaypoint(tile) {
		local town = AITile.GetClosestTown(tile);
		if (AIRail.BuildRailWaypoint(tile) ) {
			local waypoint = AIWaypoint.GetWaypointID(tile);
			local suffixes = ["Junction", "Crossing", "Point", "Union", "Switch", "Cross", "Points"]
			foreach (suffix in suffixes) {
				if (AIWaypoint.SetName(waypoint, AITown.GetName(town) + " " + suffix)) {
					break;
				}
			}
		}
	}
	
	function _tostring() {
		local station = AIStation.GetStationID(stationTile);
		local name = AIStation.IsValidStation(station) ? AIStation.GetName(station) : "unnamed";
		return "ConnectStation " + name + " to " + Crossing(crossingTile) + " " + DirectionName(direction);
	}
}

class ConnectBranchStation extends Task {
	
	crossingTile = null;
	direction = null;
	stationTile = null;
	network = null;
	
	constructor(parentTask, crossingTile, direction, stationTile, network) {
		Task.constructor(parentTask);
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
			local station = BranchStation.AtLocation(stationTile, BRANCH_STATION_PLATFORM_LENGTH);
			
			local reserved = station.GetReservedRearEntranceSpace();
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != direction) {
					reserved.extend(crossing.GetReservedEntranceSpace(d));
					reserved.extend(crossing.GetReservedExitSpace(d));
				}
			}
			
			// because the pathfinder returns a path as a linked list from the
			// goal back to the start, we build "in reverse", and because we
			// want the first signal block (from the station or junction
			// exit) to be large enough, we always want to start building
			// from that end so we actually pathfind in reverse (entrance to
			// exit) and therefore, build forward (exit to entrance)
			local from, to;
			if (network.rightSide) {
				from = Swap(crossing.GetEntrance(direction));
			} else {
				from = crossing.GetExit(direction);
			}
			
			to = station.GetEntrance();

			local buildTrack = BuildTrack(this,
				from, to,
				reserved, SignalMode.NONE, network, BuildTrack.BRANCH);
			
			subtasks.append(buildTrack);

		}
		
		RunSubtasks();
	}
	
	function _tostring() {
		local station = AIStation.GetStationID(stationTile);
		local name = AIStation.IsValidStation(station) ? AIStation.GetName(station) : "unnamed";
		return "ConnectBranchStation " + name + " to " + Crossing(crossingTile) + " " + DirectionName(direction);
	}
}

class ConnectCrossing extends Task {
	
	fromCrossingTile = null;
	fromDirection = null;
	toCrossingTile = null;
	toDirection = null;
	network = null;
	
	constructor(parentTask, fromCrossingTile, fromDirection, toCrossingTile, toDirection, network) {
		Task.constructor(parentTask);
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
		
			local reserved = network.rightSide ? toCrossing.GetReservedEntranceSpace(toDirection) : toCrossing.GetReservedExitSpace(toDirection)
			reserved.extend(network.rightSide ? fromCrossing.GetReservedExitSpace(fromDirection) : fromCrossing.GetReservedEntranceSpace(fromDirection));
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
			
			local from, to;
			if (network.rightSide) {
				from = Swap(fromCrossing.GetEntrance(fromDirection));
				to = Swap(toCrossing.GetExit(toDirection));
			} else {
				from = fromCrossing.GetExit(fromDirection);
				to = toCrossing.GetEntrance(toDirection);
			}

			local first = BuildTrack(this, from, to, reserved, SignalMode.BACKWARD, network);
			subtasks.append(first);
		
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
			
			if (network.rightSide) {
				from = Swap(toCrossing.GetEntrance(toDirection));
				to = Swap(fromCrossing.GetExit(fromDirection));
			} else {
				from = toCrossing.GetExit(toDirection);
				to = fromCrossing.GetEntrance(fromDirection);
			}
			
			subtasks.append(BuildTrack(this, from, to, reserved, SignalMode.BACKWARD, network, BuildTrack.FOLLOW, first));
		}
		
		RunSubtasks();
		
		// open up both crossings' exits
		local exit = network.rightSide ? fromCrossing.GetExit(fromDirection) : Swap(fromCrossing.GetEntrance(fromDirection));
		AIRail.RemoveSignal(exit[0], exit[1]);
		if (StartsWith(fromCrossing.GetName(), "unnamed") && AIController.GetSetting("JunctionNames")) {
			BuildWaypoint(exit[0]);
		}
		
		exit = network.rightSide ? toCrossing.GetExit(toDirection) : Swap(toCrossing.GetEntrance(toDirection));
		AIRail.RemoveSignal(exit[0], exit[1]);
		if (StartsWith(toCrossing.GetName(), "unnamed") && AIController.GetSetting("JunctionNames")) {
			BuildWaypoint(exit[0]);
		}
	}
	
	function BuildWaypoint(tile) {
		local town = AITile.GetClosestTown(tile);
		if (AIRail.BuildRailWaypoint(tile)) {
			local waypoint = AIWaypoint.GetWaypointID(tile);
			local suffixes = ["Junction", "Crossing", "Point", "Union", "Switch", "Cross", "Points"]
			foreach (suffix in suffixes) {
				if (AIWaypoint.SetName(waypoint, AITown.GetName(town) + " " + suffix)) {
					break;
				}
			}
		}
	}
	
	function _tostring() {
		return "ConnectCrossing " + Crossing(fromCrossingTile) + " " + DirectionName(fromDirection) + " to " + Crossing(toCrossingTile);
	}
}


class ExtendCrossing extends Builder {

	static MIN_TOWN_POPULATION = 300;
	
	crossing = null;
	direction = null;
	network = null;
	failedTowns = null;
	cancelled = null;
	town = null;
	candidateTowns = null;
	stationTile = null;
	crossingTile = null;
	
	constructor(parentTask, crossing, direction, network, failedTowns = null) {
		Builder.constructor(parentTask, crossing);
		this.crossing = crossing;
		this.direction = direction;
		this.network = network;
		this.failedTowns = failedTowns == null ? [] : failedTowns;
		this.cancelled = false;
		this.town = null;
		this.candidateTowns = [];
		this.stationTile = null;
		this.crossingTile = null;
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
			local towns = FindTowns(crossing, direction, MIN_TOWN_POPULATION, network.minDistance, network.maxDistance, network.maxDistance/2, true);
			towns.Valuate(AITown.GetPopulation);
			towns.Sort(AIList.SORT_BY_VALUE, false);
			local stationRotation = StationRotationForDirection(direction);
			
			// TODO: try more than station site per town?
			// NOTE: give up on a town if pathfinding fails or you might try to pathfound around the sea over and over and over...
			
			town = null;
			stationTile = null;
			for (local candidate = towns.Begin(); towns.HasNext(); candidate = towns.Next()) {
				if (ArrayContains(failedTowns, candidate)) {
					continue;
				}

				if (!town) {
					SetSecondarySign("Considering " + AITown.GetName(candidate));
					Debug("Considering " + AITown.GetName(candidate));
					stationTile = FindMainlineStationSite(candidate, stationRotation, crossing);
					if (stationTile) {
						town = candidate;
					}
				} else {
					// remember if we have other options in case this town doesn't work out
					candidateTowns.append(candidate);
				}
			}
			
			if (!stationTile) {
				throw TaskFailedException("no towns " + DirectionName(direction) + " of " + Crossing(crossing) + " where we can build a station");
			}
			
			// so we don't reforest tiles we're about to build on again
			local stationCoordinates = RelativeCoordinates(stationTile, stationRotation);
			local stationTiles = AITileList();
			stationTiles.AddRectangle(stationCoordinates.GetTile([0, 0]), stationCoordinates.GetTile([RAIL_STATION_WIDTH, RAIL_STATION_LENGTH]));

			// TODO: proper cost estimate
			// building stations is fairly cheap, but it's no use to start
			// construction if we don't have the money for pathfinding, tracks and trains 
			local costEstimate = 80000;
			
			SetSecondarySign("Looking for junction site");
			crossingTile = FindCrossingSite(stationTile);
			ClearSecondarySign();
			if (crossingTile) {
				local crossingEntranceDirection = InverseDirection(direction);
				local crossingExitDirection = CrossingExitDirection(crossingTile, stationTile);
				subtasks = [
					WaitForMoney(this, costEstimate),
					AppeaseLocalAuthority(this, town),
					BuildTownBusStation(this, town),
					LevelTerrain(this, stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2], true),
					AppeaseLocalAuthority(this, town, stationTiles),
					BuildTerminusStation(this, stationTile, direction, network, town),
					AppeaseLocalAuthority(this, town),
					BuildBusStations(this, stationTile, town),
					LevelTerrain(this, crossingTile, Rotation.ROT_0, [1, 1], [Crossing.WIDTH-2, Crossing.WIDTH-2], true),
					BuildCrossing(this, crossingTile, network),
					ConnectCrossing(this, crossing, direction, crossingTile, crossingEntranceDirection, network),
					ConnectStation(this, crossingTile, crossingExitDirection, stationTile, network),
					BuildTrains(this, stationTile, network, PAX),
				];
			} else {
				subtasks = [
					WaitForMoney(this, costEstimate),
					AppeaseLocalAuthority(this, town),
					BuildTownBusStation(this, town),
					LevelTerrain(this, stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2], true),
					AppeaseLocalAuthority(this, town, stationTiles),
					BuildTerminusStation(this, stationTile, direction, network, town),
					AppeaseLocalAuthority(this, town),
					BuildBusStations(this, stationTile, town),
					ConnectStation(this, crossing, direction, stationTile, network),
					BuildTrains(this, stationTile, network, PAX),
				];
			}
			
			// build an extra train for the second station in a network
			// at this point, that means we only have one station in the network
			if (network.stations.len() == 1) {
				local firstStation = AIStation.GetLocation(network.stations[0]);
				subtasks.append(BuildTrains(this, firstStation, network, PAX));
			}
		}
		
		RunSubtasks();

		// If a crossing was built, put its extenders into the tasks queue
		// here: first, continue onwards in the direction we're going
		// (front of the queue) but put sideways extension on the back of the
		// queue. That should create a fractal pattern of depth-first
		// expansion, returning later to fill out the internal space.
		if (crossingTile) {
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				local extender = ExtendCrossing(null, crossingTile, d, network);
				if (d == direction) {
					// index 0 is us, the currently running task
					tasks.insert(1, extender);
				} else {
					tasks.append(extender);
   				}
   			}
		}
		
		// TODO: append instead? before or after bus?
		//tasks.insert(1, ExtendStation(stationTile, direction, network));
		
		local towns = AITownList();
		towns.Valuate(AITown.GetDistanceManhattanToTile, stationTile);
		towns.KeepBelowValue(MAX_BUS_ROUTE_DISTANCE);
		
		// sort descending, then append back-to-front so the closest actually goes first
		towns.Sort(AIList.SORT_BY_VALUE, false);
		for (local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
			tasks.insert(1, BuildBusService(null, stationTile, town));
		}
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
	
	function FindCrossingSite(stationTile) {
		local dx = AIMap.GetTileX(stationTile) - AIMap.GetTileX(crossing);
		local dy = AIMap.GetTileY(stationTile) - AIMap.GetTileY(crossing);
		if (abs(dx) <= Crossing.WIDTH || abs(dy) <= Crossing.WIDTH) return null;
		
		local centerTile = crossing;
		if (direction == Direction.NE || direction == Direction.SW) {
			centerTile += AIMap.GetTileIndex(dx - Sign(dx) * (RAIL_STATION_LENGTH + 1), 0);
		} else {
			centerTile += AIMap.GetTileIndex(0, dy - Sign(dy) * (RAIL_STATION_LENGTH + 1));
		}
		
		// find a buildable area closest to ideal tile, or crossing (testing)
		local tiles = AITileList();
		SafeAddRectangle(tiles, centerTile, Crossing.WIDTH + 2);
		// this times out
		// tiles.Valuate(IsBuildableRectangle, Rotation.ROT_0, [-2, -2], [Crossing.WIDTH + 2, Crossing.WIDTH + 2], false);
		for (local tile = tiles.Begin(); tiles.HasNext(); tile = tiles.Next()) {
			tiles.SetValue(tile, IsBuildableRectangle(tile, Rotation.ROT_0, [-2, -2], [Crossing.WIDTH + 2, Crossing.WIDTH + 2], false) ? 1 : 0);
		}
		
		tiles.KeepValue(1);

		if (!tiles.IsEmpty()) {
			tiles.Valuate(LakeDetector, stationTile);
			tiles.KeepValue(0);
			tiles.Valuate(LakeDetector, crossing);
			tiles.KeepValue(0);

			if (tiles.IsEmpty()) {
				Warning("LakeDetector rejected crossing");
			}
		}
		
		// try for a more symmetrical layout by not prefering to stay close to the source crossing?
		tiles.Valuate(AIMap.DistanceManhattan, centerTile);
		// tiles.Valuate(AIMap.DistanceManhattan, crossing);

		tiles.KeepBottom(1);
		return tiles.IsEmpty() ? null : tiles.Begin();
	}
	
	function Failed() {
		Task.Failed();

		if (town && candidateTowns.len() > 0) {
			// We found a town, but failed to build or connect a station, so
			// try again in the future to see if we can expand elsewhere.
			// Since we failed, we may have troublesome geography, so expand
			// other crossings first.
			Debug(AITown.GetName(town) + " didn't work out");
			failedTowns.append(town);
			tasks.append(ExtendCrossing(null, crossing, direction, network, failedTowns));
			
			// leave the exit in place
			return;
		} else {
			Debug("no towns left to try");

			// maybe we can still build a branch line
			tasks.append(BuildBranchLine(null, crossing, direction, network));

			// leave the exit in place
			return;
		}
		
		// either we didn't find a town, or one of our subtasks failed
		local entrance = Crossing(crossing).GetEntrance(direction);
		local exit = Crossing(crossing).GetExit(direction);
		
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
		if (location == crossing) {
			SetLocalCoordinateSystem(GetTile(offset), rotation);
		}
		
		// the exit might have a waypoint
		if (network.rightSide) {
			Demolish([0,2]);
		} else {
			Demolish([0,1]);
		}
		
		RemoveRail([-1,1], [0,1], [1,1]);
		RemoveRail([-1,2], [0,2], [1,2]);
		
		RemoveRail([0,1], [1,1], [1,0]);
		RemoveRail([0,1], [1,1], [2,1]);
		
		RemoveRail([0,2], [1,2], [2,2]);
		RemoveRail([0,2], [1,2], [1,3]);
		
		RemoveRail([2,2], [2,1], [1,1]);
		RemoveRail([2,1], [2,2], [1,2]);
		
		// we can remove more bits if another direction is already gone
		if (!HasRail([1,3]) && !HasRail([2,3])) {
			RemoveRail([1,1], [2,1], [3,1]);
			RemoveRail([2,0], [2,1], [2,2]);
			RemoveRail([2,1], [2,2], [2,3]);
		}
		
		if (!HasRail([1,0]) && !HasRail([1,0])) {
			RemoveRail([1,2], [2,2], [3,2]);
			RemoveRail([2,0], [2,1], [2,2]);
			RemoveRail([2,1], [2,2], [2,3]);
		}

		// TODO if only two directions remain, rename from "crossing"/"junction" to "waypoint"
	}
	
	function HasRail(tileCoords) {
		return AIRail.IsRailTile(GetTile(tileCoords));
	}
}
