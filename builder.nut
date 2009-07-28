const RAIL_STATION_RADIUS = 4;
const RAIL_STATION_PLATFORM_LENGTH = 3;
const RAIL_STATION_LENGTH = 8;	// actual building and rails plus room for entrance/exit
const RAIL_STATION_WIDTH = 2;

class Builder extends Task {
	
	relativeCoordinates = null;
	location = null;
	rotation = null;
	
	constructor(location, rotation = Rotation.ROT_0) {
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}
	
	function GetLocationString(tile = null) {
		if (tile == null) tile = this.location;
		return "(" + AIMap.GetTileX(tile) + ", " + AIMap.GetTileY(tile) + ")";
	}
	
	function GetTile(coordinates) {
		return relativeCoordinates.GetTile(coordinates);
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
	 * Remove rail, see BuildRail.
	 */
	function RemoveRail(from, on, to, check = false) {
		AIRail.RemoveRail(GetTile(from), GetTile(on), GetTile(to));
		if (check) CheckError();
	}
	
	function BuildSignal(tile, front, type) {
		AIRail.BuildSignal(GetTile(tile), GetTile(front), type);
		CheckError();
	}
	
	function BuildDepot(tile, front) {
		AIRail.BuildRailDepot(GetTile(tile), GetTile(front));
		CheckError();
	}

	function Demolish(tile) {
		AITile.DemolishTile(GetTile(tile));
		// CheckError()?
	}
	
}

class BuildLine extends Task {
	
	static MIN_TOWN_POPULATION = 300;
	static MIN_TOWN_DISTANCE = 50;
	static MAX_TOWN_DISTANCE = 100;
	
	static wrapper = [];
	
	function _tostring() {
		return "BuildLine";
	}
	
	function Run() {
		local towns = FindTownPair();
		local a = towns[0];
		local b = towns[1];
		
		local nameA = AITown.GetName(a);
		local dirA = StationDirection(a, b);
		local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
		local siteA = FindStationSite(a, rotA, AITown.GetLocation(b));

		local nameB = AITown.GetName(b);
		local dirB = StationDirection(b, a);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		local siteB = FindStationSite(b, rotB, AITown.GetLocation(a));
		
		if (siteA && siteB) {
			Debug("Connecting " + nameA + " and " + nameB);
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return Retry();
		}
		
		local exitA = TerminusStation(siteA, rotA, RAIL_STATION_PLATFORM_LENGTH).GetEntrance();
		local exitB = TerminusStation(siteB, rotB, RAIL_STATION_PLATFORM_LENGTH).GetEntrance();
		
		local network = Network(AIRailTypeList().Begin(), MIN_TOWN_DISTANCE, MAX_TOWN_DISTANCE);
		local subtasks = [
			BuildTerminusStation(siteA, dirA, network),
			BuildTerminusStation(siteB, dirB, network),
			BuildTrack(exitA, exitB, [], SignalMode.NONE, network),
			BuildTrains(siteA, network, AIOrder.AIOF_FULL_LOAD_ANY, true),
			BuildBusStations(siteA, a),
			BuildBusStations(siteB, b),
		];
		
		tasks.insert(1, TaskList(this, subtasks));
	}
	
	function FindTownPair() {
		local pairs;
		
		if (wrapper.len() == 0) {
			Debug("Generating list of viable town pairs...");
			local towns = AITownList();
			towns.Valuate(AITown.GetPopulation);
			towns.KeepAboveValue(MIN_TOWN_POPULATION);
			
			local copy = AIList();
			copy.AddList(towns);
			
			pairs = AIList();
			for (local a = towns.Begin(); towns.HasNext(); a = towns.Next()) {
				for (local b = copy.Begin(); copy.HasNext(); b = copy.Next()) {
					// store two 16-bit town IDs in one 32-bit list item, and valuate them with their distance
					local pair = a + (b << 16);
					pairs.AddItem(pair, AITown.GetDistanceManhattanToTile(a, AITown.GetLocation(b)));
				}
			}
			
			pairs.KeepAboveValue(MIN_TOWN_DISTANCE);
			pairs.KeepBelowValue(MAX_TOWN_DISTANCE);
			if (pairs.IsEmpty()) throw TaskFailed("no suitable towns");
			
			wrapper.append(pairs);
		} else {
			pairs = wrapper[0];
		}
		
		pairs.Valuate(AIBase.RandItem);
		pairs.Sort(AIList.SORT_BY_VALUE, true);
		local pair = pairs.Begin();
		return [pair & 0xFFFF, pair >> 16];
	}
	
	function StationDirection(fromTown, toTown) {
		local dx = AIMap.GetTileX(AITown.GetLocation(fromTown)) - AIMap.GetTileX(AITown.GetLocation(toTown));
		local dy = AIMap.GetTileY(AITown.GetLocation(fromTown)) - AIMap.GetTileY(AITown.GetLocation(toTown));
		
		if (abs(dx) > abs(dy)) {
			return dx > 0 ? Direction.SW : Direction.NE;
		} else {
			return dy > 0 ? Direction.SE : Direction.NW;
		}
	}
}

class BuildNewNetwork extends Builder {
	
	network = null;
	
	constructor(minDistance = MIN_DISTANCE, maxDistance = MAX_DISTANCE) {
		this.network = Network(AIRailTypeList().Begin(), minDistance, maxDistance);
	}
	
	function Run() {
		local tile;
		
		while (true) {
			tile = RandomTile();
			if (AIMap.IsValidTile(tile) &&
				AITile.IsBuildableRectangle(
					tile - AIMap.GetTileIndex(Crossing.WIDTH, Crossing.WIDTH),
					Crossing.WIDTH*3, Crossing.WIDTH*3) &&
				EstimateNetworkStationCount(tile) >= 2) break;
		}
		
		AIRail.SetCurrentRailType(network.railType);
		tasks.insert(1, TaskList(this, [
			LevelTerrain(tile, Rotation.ROT_0, [-1, -1], [Crossing.WIDTH + 1, Crossing.WIDTH + 1]),
			BuildCrossing(tile, network)
		]));
	}
	
	function _tostring() {
		return "BuildNewNetwork";
	}
	
	function EstimateNetworkStationCount(tile) {
		local stationCount = 0;
		local estimationNetwork = Network(network.railType, network.minDistance, network.maxDistance);
		foreach (direction in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
			stationCount += EstimateCrossing(tile, direction, estimationNetwork);
		}
		
		Debug("Estimated stations for crossing at " + GetLocationString(tile) + ": " + stationCount);
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
	
	network = null;
	
	constructor(location, network) {
		Builder.constructor(location);
		this.network = network;
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
		local type = AIRail.SIGNALTYPE_PBS_ONEWAY;
		BuildSignal([0,1], [-1, 1], type);
		BuildSignal([0,2], [-1, 2], type);
		BuildSignal([1,3], [ 1, 4], type);
		BuildSignal([2,3], [ 2, 4], type);
		BuildSignal([3,2], [ 4, 2], type);
		BuildSignal([3,1], [ 4, 1], type);
		BuildSignal([2,0], [ 2,-1], type);
		BuildSignal([1,0], [ 1,-1], type);
		
		// cap entrances off with depots
		//BuildDepot([-1,1], [0,1]);
		//BuildDepot([-1,2], [0,2]);
		//BuildDepot([ 1,4], [1,3]);
		//BuildDepot([ 2,4], [2,3]);
		//BuildDepot([ 4,2], [3,2]);
		//BuildDepot([ 4,1], [3,1]);
		//BuildDepot([2,-1], [2,0]);
		//BuildDepot([1,-1], [1,0]);
		
		world.crossings[location] <- Crossing(location);
		
		// expand in opposite directions first, to maximize potential gains
		tasks.push(ExtendCrossing(location, Direction.NE, network));
		tasks.push(ExtendCrossing(location, Direction.SW, network));
		tasks.push(ExtendCrossing(location, Direction.NW, network));
		tasks.push(ExtendCrossing(location, Direction.SE, network));
	}
	
	function _tostring() {
		return "BuildCrossing " + GetLocationString();
	}
	
	function Failed() {
		AISign.RemoveSign(location);
	}
}

/**
 * 2-platform terminus station.
 */
class BuildTerminusStation extends Builder {
	
	network = null;
	platformLength = null;
	builtPlatform1 = null;
	builtPlatform2 = null;
	
	constructor(location, direction, network, platformLength = RAIL_STATION_PLATFORM_LENGTH) {
		Builder.constructor(location, StationRotationForDirection(direction));
		this.network = network;
		this.platformLength = platformLength;
		this.builtPlatform1 = false;
		this.builtPlatform2 = false;
	}
	
	function Run() {
		BuildPlatforms();
		local p = platformLength;
		BuildSegment([0, p], [0, p+1]);
		BuildSegment([1, p], [1, p+1]);
		BuildRail([0, p-1], [0, p], [1, p+1]);
		BuildRail([1, p-1], [1, p], [0, p+1]);
		BuildSignal([0, p+1], [0, p+2], AIRail.SIGNALTYPE_PBS);
		BuildSignal([1, p+1], [1, p], AIRail.SIGNALTYPE_PBS);
		world.stations[location] <- TerminusStation(location, rotation, platformLength);
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
		world.stations[location] <- null;
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
		return "BuildTerminusStation " + GetLocationString();
	}
}

/**
 * Increase the capture area of a train station by joining bus stations to it.
 */
class BuildBusStations extends Builder {

	stationTile = null;
	town = null;
		
	constructor(stationTile, town) {
		this.stationTile = stationTile;
		this.town = town;
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
				area.RemoveRectangle(tile - AIMap.GetTileIndex(2, 2), tile + AIMap.GetTileIndex(2, 2));
			}
		}
	}
	
	function BuildStationAt(tile) {
		if (BuildStation(tile, true) || BuildStation(tile, false)) {
			return true;
		}
		
		return false;
	}
	
	function BuildStation(tile, facing) {
		local front = tile + (facing ? AIMap.GetTileIndex(0,1) : AIMap.GetTileIndex(1,0));
		return AIRoad.BuildDriveThroughRoadStation(tile, front, AIRoad.ROADVEHTYPE_BUS, AIStation.GetStationID(stationTile));
	}
}

class BuildTrack extends Builder {

	static SIGNAL_INTERVAL = 3;
	static DEPOT_INTERVAL = 15;
	
	a = null;
	b = null;
	c = null;
	d = null;
	ignored = null;
	signalMode = null;
	network = null;
	path = null;
	count = null;
	lastDepot = null;
	
	constructor(from, to, ignored, signalMode, network) {
		this.a = from[0];
		this.b = from[1];
		this.c = to[0];
		this.d = to[1];
		this.ignored = ignored;
		this.signalMode = signalMode;
		this.network = network;
		this.count = 1;
		this.lastDepot = -DEPOT_INTERVAL;	// build one as soon as possible
		this.path = null;
	}
	
	function _tostring() {
		return "BuildTrack";
	}
	
	function Run() {
		/*
		AISign.BuildSign(a, "a");
		AISign.BuildSign(b, "b");
		AISign.BuildSign(c, "c");
		AISign.BuildSign(d, "d");
		*/
		
		if (!path) path = FindPath(a, b, c, d, ignored);
		if (!path) return TaskFailed("no path");
		BuildPath(path);
	}
	
	function FindPath(a, b, c, d, ignored) {
		local pathfinder = Rail();
		
		pathfinder.cost.max_bridge_length = 20;
		pathfinder.cost.max_tunnel_length = 20;
		pathfinder.estimate_multiplier = 2;
		
		pathfinder.cost.max_cost = pathfinder.cost.tile * 4 * AIMap.DistanceManhattan(a, d);
		pathfinder.cost.diagonal_tile = 200;
		pathfinder.cost.bridge_per_tile = 500;
		pathfinder.cost.tunnel_per_tile = 500;
		
		// Pathfinding needs money since it attempts to build in test mode.
		// We can't get the price of a tunnel, but we can get it for a bridge
		// and we'll assume they're comparable.
		local maxBridgeCost = GetMaxBridgeCost(pathfinder.cost.max_bridge_length);
		if (GetBankBalance() < maxBridgeCost*2) {
			throw NeedMoney(maxBridgeCost*2);
		}
		
		Debug("Pathfinding...");
		pathfinder.InitializePath([[b, a]], [[c, d]], ignored);
		return pathfinder.FindPath(AIMap.DistanceManhattan(a, d) * 10 * TICKS_PER_DAY);
	}
	
	function GetMaxBridgeCost(length) {
		local bridges = AIBridgeList_Length(length);
		if (bridges.IsEmpty()) throw "Cannot build " + length + " tile bridges!";
		bridges.Valuate(AIBridge.GetMaxSpeed);
		bridges.KeepTop(1);
		local bridge = bridges.Begin();
		return AIBridge.GetPrice(bridge, length);
	}
	
	function BuildPath(path) {
		Debug("Building...");
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		while (node != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, node.GetTile()) > 1) {
					if (AITunnel.GetOtherTunnelEnd(prev) == node.GetTile()) {
						// since we can resume building, check if there already is a tunnel
						if (!AITunnel.IsTunnelTile(prev)) {
							AITunnel.BuildTunnel(AIVehicle.VT_RAIL, prev);
							CheckError();
						}
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(node.GetTile(), prev) + 1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);
						AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, node.GetTile());
						CheckError();
					}
					prevprev = prev;
					prev = node.GetTile();
					node = node.GetParent();
				} else {
					local built = AIRail.BuildRail(prevprev, prev, node.GetTile());
					CheckError();
					
					// since we can be restarted, we can process a tile more than once
					// don't build signals again, or they'll be flipped around!
					local forward = signalMode == SignalMode.FORWARD;
					local front = forward ? node.GetTile() : prevprev;
					if (signalMode != SignalMode.NONE &&
					    count % SIGNAL_INTERVAL == 0 &&
					    AIRail.GetSignalType(prev, front) == AIRail.SIGNALTYPE_NONE)
					{
						AIRail.BuildSignal(prev, front, AIRail.SIGNALTYPE_NORMAL);
					}
					
					local possibleDepot = prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), forward) : null;
					if (count % SIGNAL_INTERVAL == 1 && count - lastDepot > DEPOT_INTERVAL && depotSite) {
						if (AIRail.BuildRailDepot(depotSite, prev) &&
							AIRail.BuildRail(depotSite, prev, prevprev) &&
							AIRail.BuildRail(depotSite, prev, node.GetTile())) {
							// success
							lastDepot = count;
							network.depots.append(depotSite);
						} else {
							AITile.DemolishTile(depotSite);
							AIRail.RemoveRail(depotSite, prev, prevprev);
							AIRail.RemoveRail(depotSite, prev, node.GetTile());
						}							
					}
					
					if (built) count++;
				}
			}
			if (node != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = node.GetTile();
				node = node.GetParent();
			}
		}
		
		Debug("Done!");
	}
	
	/**
	 * Return a tile suitable for building a depot, or null.
	 */
	function GetDepotSite(prevprev, prev, tile, next, nextnext, forward) {
		// depots are built off to the right side of the track
		// site is suitable if the tiles are in a straight X or Y line
		local coordinates = [
			TileCoordinates(prevprev),
			TileCoordinates(prev),
			TileCoordinates(tile),
			TileCoordinates(next),
			TileCoordinates(nextnext)
		];
		
		local depotSite = null;
		if (MatchCoordinates(coordinates, 0)) {
			// same X
			if (coordinates[0][1] < coordinates[1][1]) {
				// increasing Y
				depotSite = AIMap.GetTileIndex(coordinates[2][0] + (forward ? -1 : 1), coordinates[2][1]);
			} else {
				// decreasing Y
				depotSite = AIMap.GetTileIndex(coordinates[2][0] + (forward ? 1 : -1), coordinates[2][1]);
			}
			
		} else if (MatchCoordinates(coordinates, 1)) {
			// same Y
			if (coordinates[0][0] < coordinates[1][0]) {
				// increasing X
				depotSite = AIMap.GetTileIndex(coordinates[2][0], coordinates[2][1] + (forward ? 1 : -1));
			} else {
				// decreasing X
				depotSite = AIMap.GetTileIndex(coordinates[2][0], coordinates[2][1] + (forward ? -1 : 1));
			}
		}
		
		return (depotSite && AITile.IsBuildable(depotSite)) ? depotSite : null; 
	}
	
	/**
	 * Test whether the X or Y coordinates of a list are all the same.
	 */
	function MatchCoordinates(coordinates, index) {
		local value = coordinates[0][index];
		foreach (c in coordinates) {
			if (c[index] != value) return false;
		}
		
		return true;
	}
	
	function TileCoordinates(tile) {
		return [AIMap.GetTileX(tile), AIMap.GetTileY(tile)];
	}
}

class ConnectStation extends Builder {
	
	crossingTile = null;
	direction = null;
	stationTile = null;
	network = null;
	bt1 = null;
	bt2 = null;
	
	constructor(crossingTile, direction, stationTile, network) {
		this.crossingTile = crossingTile;
		this.direction = direction;
		this.stationTile = stationTile;
		this.network = network;
		this.bt1 = null;
		this.bt2 = null;
	}
	
	function Run() {
		local crossing = world.crossings[crossingTile];
		local station = world.stations[stationTile];
		
		// if we ran these subtasks as a task list, we can't signal failure to our parent task list
		// so, we run them inline, making sure we can be restarted
		// TODO: clean this up?
		
		if (bt1 == null) {
			local reserved = station.GetReservedEntranceSpace();
			reserved.extend(crossing.GetReservedExitSpace(direction));
			foreach (d in [Direction.NE, Direction.SW, Direction.NW, Direction.SE]) {
				if (d != direction) {
					reserved.extend(crossing.GetReservedEntranceSpace(d));
					reserved.extend(crossing.GetReservedExitSpace(d));
				}
			}
			
			bt1 = BuildTrack(station.GetExit(), crossing.GetEntrance(direction), reserved, SignalMode.FORWARD, network);
		}
		
		if (bt2 == null) {
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
			
			bt2 = BuildTrack(Swap(station.GetEntrance()), Swap(crossing.GetExit(direction)), reserved, SignalMode.BACKWARD, network);
		}
		
		bt1.Run();
		bt2.Run();
		
		// building another signal on the tile will flip it, opening up the exit
		local exit = crossing.GetExit(direction);
		AIRail.BuildSignal(exit[0], exit[1], AIRail.SIGNALTYPE_PBS_ONEWAY);
	}
	
	function Swap(tiles) {
		return [tiles[1], tiles[0]];
	}
	
	function _tostring() {
		return "ConnectStation";
	}
}

class ConnectCrossing extends Builder {
	
	fromCrossingTile = null;
	fromDirection = null;
	toCrossingTile = null;
	toDirection = null;
	network = null;
	bt1 = null;
	bt2 = null;
	
	constructor(fromCrossingTile, fromDirection, toCrossingTile, toDirection, network) {
		this.fromCrossingTile = fromCrossingTile;
		this.fromDirection = fromDirection;
		this.toCrossingTile = toCrossingTile;
		this.toDirection = toDirection;
		this.network = network;
		this.bt1 = null;
		this.bt2 = null;
	}
	
	function Run() {
		local fromCrossing = world.crossings[fromCrossingTile];
		local toCrossing = world.crossings[toCrossingTile];
		
		if (bt1 == null) {
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
			
			bt1 = BuildTrack(toCrossing.GetExit(toDirection), fromCrossing.GetEntrance(fromDirection), reserved, SignalMode.FORWARD, network);
		}
		
		if (bt2 == null) {
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
			
			bt2 = BuildTrack(Swap(toCrossing.GetEntrance(toDirection)), Swap(fromCrossing.GetExit(fromDirection)), reserved, SignalMode.BACKWARD, network);
		}
		
		bt1.Run();
		bt2.Run();
		
		// open up both crossings' exits
		local exit = fromCrossing.GetExit(fromDirection);
		AIRail.BuildSignal(exit[0], exit[1], AIRail.SIGNALTYPE_PBS_ONEWAY);
		
		exit = toCrossing.GetExit(toDirection);
		AIRail.BuildSignal(exit[0], exit[1], AIRail.SIGNALTYPE_PBS_ONEWAY);
	}
	
	function Swap(tiles) {
		return [tiles[1], tiles[0]];
	}
	
	function _tostring() {
		return "ConnectCrossing";
	}
}

class ExtendCrossing extends Builder {

	crossing = null;
	direction = null;
	network = null;
	
	constructor(crossing, direction, network) {
		Builder.constructor(crossing);
		this.crossing = crossing;
		this.direction = direction;
		this.network = network;
	}
	
	function _tostring() {
		return "ExtendCrossing " + GetLocationString();
	}
	
	function Run() {
		// see if we''ve not already built this direction
		local entrance = world.crossings[crossing].GetEntrance(direction);
		if (AIRail.IsRailTile(entrance[0])) {
			return;
		}
		
		// do the math
		local towns = FindTowns();
		local town = null;
		local stationTile = null;
		for (town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
			stationTile = FindStationSite(town, BuildTerminusStation.StationRotationForDirection(direction), crossing);
			if (stationTile) break;
		}
		
		if (!stationTile) {
			return TaskFailed("no towns where we can build a station");
		}
		
		local crossingTile = FindCrossingSite(stationTile);
		
		// do the work
		local subtasks;
		if (crossingTile) {
			local crossingEntranceDirection = InverseDirection(direction);
			local crossingExitDirection = CrossingExitDirection(crossingTile, stationTile);
			
			subtasks = [
				BuildTerminusStation(stationTile, direction, network),
				LevelTerrain(crossingTile, Rotation.ROT_0, [-1, -1], [Crossing.WIDTH + 1, Crossing.WIDTH + 1]),
				BuildCrossing(crossingTile, network),
				ConnectCrossing(crossing, direction, crossingTile, crossingEntranceDirection, network),
				ConnectStation(crossingTile, crossingExitDirection, stationTile, network),
				BuildTrains(stationTile, network),
				BuildBusStations(stationTile, town),
			];
		} else {
			subtasks = [
				BuildTerminusStation(stationTile, direction, network),
				ConnectStation(crossing, direction, stationTile, network),
				BuildTrains(stationTile, network),
				BuildBusStations(stationTile, town),
			];
		}
		
		tasks.insert(1, TaskList(this, subtasks));
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
		foreach (key, value in world.stations) {
			local station = AIStation.GetStationID(key);
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
	
	function Failed() {
		// remove the pieces of track for this direction
		local entrance = Crossing(location).GetEntrance(direction);
		//AIRail.RemoveSignal(entrance[1], entrance[0]);
		//AIRail.BuildRailDepot(entrance[0], entrance[1]);
		
		local exit = Crossing(location).GetExit(direction);
		//AIRail.RemoveSignal(exit[0], exit[1]);
		//AIRail.BuildRailDepot(exit[1], exit[0]);
		
		switch (direction) {
			case Direction.NE:
				RemoveRail([0,1], [1,1], [1,0]);
				RemoveRail([0,1], [1,1], [2,1]);
				
				RemoveRail([0,2], [1,2], [2,2]);
				RemoveRail([0,2], [1,2], [1,3]);
				break;
				
			case Direction.SE:
				RemoveRail([1,3], [1,2], [1,1]);
				RemoveRail([1,3], [1,2], [0,2]);
				
				RemoveRail([2,3], [2,2], [2,1]);
				RemoveRail([2,3], [2,2], [3,2]);
				break;
				
			case Direction.SW:
				RemoveRail([3,2], [2,2], [2,3]);
				RemoveRail([3,2], [2,2], [1,2]);
				
				RemoveRail([3,1], [2,1], [2,0]);
				RemoveRail([3,1], [2,1], [1,1]);
				break;
				
			case Direction.NW:
				RemoveRail([1,0], [1,1], [0,1]);
				RemoveRail([1,0], [1,1], [1,2]);
				
				RemoveRail([2,0], [2,1], [3,1]);
				RemoveRail([2,0], [2,1], [2,2]);
				break;
				
			default: throw "invalid direction";
		}
		
		AITile.DemolishTile(entrance[1]);
		AITile.DemolishTile(exit[0]);
	}
}

class BuildTrains extends Task {
	
	static TRAINS_ADDED_PER_STATION = 3;
	
	stationTile = null;
	network = null;
	flags = null;
	cheap = null;
	depot = null;
	engine = null;
	
	constructor(stationTile, network, flags = null, cheap = false) {
		this.stationTile = stationTile;
		this.network = network;
		this.flags = flags == null ? AIOrder.AIOF_NONE : AIOrder.AIOF_FULL_LOAD_ANY;
		this.cheap = cheap;
	}
	
	function _tostring() {
		return "BuildTrains";
	}
	
	function Run() {
		local depotList = AIList();
		foreach (depot in network.depots) {
			depotList.AddItem(depot, 0);
		}
		
		depotList.Valuate(AIMap.DistanceManhattan, stationTile);
		depotList.KeepBottom(1);
		if (depotList.IsEmpty()) {
			// nowhere to build trains
			return;
		}
		
		local depot = depotList.Begin();
		local from = AIStation.GetStationID(stationTile);
		
		// add trains to the N stations with the greatest capacity deficit
		local stationList = ArrayToList(network.stations);
		stationList.RemoveItem(from);
		stationList.Valuate(StationCapacityDeficit);
		stationList.KeepTop(TRAINS_ADDED_PER_STATION);
		
		for (local to = stationList.Begin(); stationList.HasNext(); to = stationList.Next()) {
			Debug("Adding train to " + AIStation.GetName(to));
			tasks.insert(1, BuildTrain(to, from, depot, network, flags));
		}
	}
	
	/**
	 * Calculates the difference between the amount of cargo/passengers produced
	 * and the transport capacity of currently assigned trains.
	 */
	function StationCapacityDeficit(station) {
		local production = AITown.GetMaxProduction(AIStation.GetNearestTown(station), PAX);
		local trains = AIVehicleList_Station(station);
		trains.Valuate(BuildTrains.TrainCapacity);
		local capacity = Sum(trains);
		
		//Debug("Station " + AIStation.GetName(station) + " production: " + production + ", capacity: " + capacity + ", deficit: " + (production - capacity));
		return production - capacity;
	}
	
	/**
	 * Estimates train capacity in terms of cargo/passengers transported per month.
	 * Speed conversion from http://wiki.openttd.org/Game_mechanics#Vehicle_speeds:
	 * 160 km/h = 5.6 tiles/day, so 1 km/h = 0.035 tiles/day = 1.05 tiles/month.
	 */ 
	function TrainCapacity(train) {
		local capacity = AIVehicle.GetCapacity(train, PAX);
		
		local a = AIOrder.GetOrderDestination(train, 0);
		local b = AIOrder.GetOrderDestination(train, 1);
		local distance = AIMap.DistanceManhattan(a, b);
		
		local speedKph = AIEngine.GetMaxSpeed(AIVehicle.GetEngineType(train)) / 2;
		local speedTpm = speedKph * 1.05;
		local triptime = distance/speedTpm;
		
		//Debug("Vehicle " + AIVehicle.GetName(train) + " at speed " + speedKph + " km/h can travel " +
		//	distance + " tiles in " + triptime + " months with " + capacity + " passengers");
		
		return (capacity/triptime).tointeger();
	}
	
		
	
}

class BuildTrain extends Builder {
	
	static TRAIN_LENGTH = 3;	// in tiles
	static bannedEngines = [];
	
	from = null;
	to = null;
	depot = null;
	network = null;
	cheap = null;
	flags = null;
	train = null;
	hasMail = null;
	
	constructor(from, to, depot, network, flags, cheap = false) {
		this.from = from;
		this.to = to;
		this.depot = depot;
		this.network = network;
		this.flags = flags;
		this.cheap = cheap;
		this.train = null;
		this.hasMail = false;
	}
	
	function _tostring() {
		return "BuildTrain " + GetLocationString(depot);
	}
	
	function Run() {
		// we need an engine
		if (!train || !AIVehicle.IsValidVehicle(train)) {
			//Debug("Building locomotive at " + AIMap.GetTileX(depot) + "," + AIMap.GetTileY(depot));
			local engineType = GetEngine(network.railType, cheap);
			train = AIVehicle.BuildVehicle(depot, engineType);
			
			// locomotives are expensive compared to other things we build
			if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
				return NeedMoney(AIEngine.GetPrice(engineType));
			}
			
			CheckError();
		}
		
		// one mail wagon
		if (!hasMail) {
			local wagonType = GetWagon(MAIL, network.railType);
			if (wagonType) {
				local wagon = AIVehicle.BuildVehicle(depot, wagonType);
				CheckError();
				AIVehicle.MoveWagon(wagon, 0, train, 0);
				CheckError();
			} else {
				// no mail wagons available - can happen in some train sets
				// just skip it, we'll build another passenger wagon instead
			}
			
			// moving it into the train makes it stop existing as a separate vehicleID,
			// so use a boolean flag, not a vehicle ID
			hasMail = true;
		}
		
		// and fill the rest of the train with passenger wagons
		local wagonType = GetWagon(PAX, network.railType);
		while (AIVehicle.GetLength(train)/16 < TRAIN_LENGTH) {
			local wagon = AIVehicle.BuildVehicle(depot, wagonType);
			CheckError();
			
			if (!AIVehicle.MoveWagon(wagon, 0, train, 0)) {
				// can't add passenger wagons to this type of engine, so don't build it again
				bannedEngines.append(AIVehicle.GetEngineType(train));
				
				// sell it and try again
				AIVehicle.SellVehicle(train);
				AIVehicle.SellVehicle(wagon);
				train = null;
				return Retry();
			}
		}

		network.trains.append(train);
		AIOrder.AppendOrder(train, AIStation.GetLocation(from), flags);
		AIOrder.AppendOrder(train, AIStation.GetLocation(to), flags);
		AIVehicle.StartStopVehicle(train);
	}
	
	function GetEngine(railType, cheap) {
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.IsWagon);
		engineList.KeepValue(0);
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.HasPowerOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.CanPullCargo, PAX);
		engineList.KeepValue(1);
		engineList.RemoveList(ArrayToList(bannedEngines));
		
		engineList.Valuate(AIEngine.GetPrice);
		if (cheap) {
			// go for the cheapest
			engineList.KeepBottom(1);
		} else {
			// pick something middle of the range, by removing the top half
			// this will hopefully give us something decent, even when faced with newgrf train sets
			engineList.Sort(AIList.SORT_BY_VALUE, true);
			engineList.RemoveTop(engineList.Count() / 2);
		}
		
		if (engineList.IsEmpty()) throw TaskFailed("no suitable engine");
		return engineList.Begin();
	}
	
	function GetWagon(cargoID, railType) {
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.CanRefitCargo, cargoID);
		engineList.KeepValue(1);

		engineList.Valuate(AIEngine.IsWagon);
		engineList.KeepValue(1);
		
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);

		engineList.Valuate(AIEngine.GetCapacity)
		engineList.KeepTop(1);
		
		return engineList.IsEmpty() ? null : engineList.Begin();
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
		AITile.LevelTiles(GetTile(from), GetTile(to));
		CheckError();
	}
	
	function _tostring() {
		return "LevelTerrain";
	}
	
}

/**
 * Find a site for a station at the given town, as close as possible
 * to the destination tile.
 */
function FindStationSite(town, stationRotation, destination) {
	local location = AITown.GetLocation(town);
	
	local area = AITileList();
	SafeAddRectangle(area, location, 20);
	
	// only tiles that "belong" to the town
	area.Valuate(AITile.GetClosestTown)
	area.KeepValue(town);
	
	// room for a station
	area.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], true);
	area.KeepValue(1);
	
	// must accept and produce passengers
	area.Valuate(AITile.GetCargoAcceptance, PAX, 1, 1, RAIL_STATION_RADIUS);
	area.KeepAboveValue(7);
	area.Valuate(AITile.GetCargoProduction, PAX, 1, 1, RAIL_STATION_RADIUS);
	area.KeepAboveValue(7);
	
	// pick the tile closest to the crossing
	area.Valuate(AITile.GetDistanceManhattanToTile, destination);
	area.KeepBottom(1);
	
	return area.IsEmpty() ? null : area.Begin();
}

function IsBuildableRectangle(location, rotation, from, to, mustBeFlat) {
	// check if the area is clear and flat
	// TODO: don't require it to be flat, check if it can be leveled
	local coords = RelativeCoordinates(location, rotation);
	local height = AITile.GetHeight(location);
	for (local x = from[0]; x < to[0]; x++) {
		for (local y = from[1]; y < to[1]; y++) {
			local tile = coords.GetTile([x, y]);
			local flat = AITile.GetHeight(tile) == height && AITile.GetMinHeight(tile) == height && AITile.GetMaxHeight(tile) == height;
			if (!AITile.IsBuildable(tile) || (mustBeFlat && !flat)) {
				return false;
			}
		}
	}
	
	return true;
}