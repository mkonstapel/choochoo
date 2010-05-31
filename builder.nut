const RAIL_STATION_RADIUS = 4;
const RAIL_STATION_WIDTH = 3;
const RAIL_STATION_PLATFORM_LENGTH = 3;
const RAIL_STATION_LENGTH = 6; // actual building and rails plus room for entrance/exit

class Builder extends Task {
	
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
	
	function SetLocalCoordinateSystem(location, rotation) {
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}
	
	/**
	 * Build a non-diagonal segment of track.
	 */
	function BuildSegment(start, end) {
		DoSegment(start, end, true);
	}
	
	/**
	 * Remove a non-diagonal segment of track.
	 */
	function RemoveSegment(start, end) {
		DoSegment(start, end false);
	}
	
	function DoSegment(start, end, build) {
		local from, to;
		if (start[0] == end[0]) {
			from = [start[0], start[1] - 1];
			to = [end[0], end[1] + 1];
		} else {
			from = [start[0] - 1, start[1]];
			to = [end[0] + 1, end[1]];
		}
		
		if (build)
			BuildRail(from, start, to);
		else
			RemoveRail(from, start, to);
	}
	
	/**
	 * Build a straight piece of track, excluding 'from' and 'to'.
	 */
	function BuildRail(from, on, to) {
		AIRail.BuildRail(GetTile(from), GetTile(on), GetTile(to));
		CheckError();
	}
	
	/**
	 * Remove rail, see BuildRail. If a vehicle is in the way, wait and retry.
	 */
	function RemoveRail(from, on, to, check = false) {
		while (true) {
			AIRail.RemoveRail(GetTile(from), GetTile(on), GetTile(to));
			if (AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) {
				AIController.Sleep(1);
			} else {
				break;
			}
		}
		
		if (check) CheckError();
	}
	
	function BuildSignal(tile, front, type) {
		// if we build a signal again on a tile that already has one,
		// it'll be turned the other way, so check before we build
		if (AIRail.GetSignalType(GetTile(tile), GetTile(front)) == AIRail.SIGNALTYPE_NONE) {
			AIRail.BuildSignal(GetTile(tile), GetTile(front), type);
			CheckError();
		}
	}
	
	function BuildDepot(tile, front) {
		AIRail.BuildRailDepot(GetTile(tile), GetTile(front));
		CheckError();
	}
	
	function BuildSign(tile, text) {
		AISign.BuildSign(GetTile(tile), text);
		CheckError();
	}
	
	function Demolish(tile) {
		AITile.DemolishTile(GetTile(tile));
		// CheckError()?
	}
	
}

class BuildLine extends TaskList {
	
	static MIN_TOWN_POPULATION = 500;
	static MIN_TOWN_DISTANCE = 30;
	static MAX_TOWN_DISTANCE = 100;
	
	static wrapper = [];
	
	constructor() {
		TaskList.constructor(this, null);
	}
	
	function _tostring() {
		return "BuildLine";
	}
	
	function Run() {
		if (!subtasks) {
			local towns = FindTownPair();
			local a = towns[0];
			local b = towns[1];
			
			local nameA = AITown.GetName(a);
			local dirA = StationDirection(AITown.GetLocation(a), AITown.GetLocation(B));
			local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
			local siteA = FindStationSite(a, rotA, AITown.GetLocation(b));
	
			local nameB = AITown.GetName(b);
			local locB = AITown.GetLocation(b);
			local dirB = StationDirection(AITown.GetLocation(b), AITown.GetLocation(a));
			local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
			local siteB = FindStationSite(b, rotB, AITown.GetLocation(a));
			
			if (siteA && siteB) {
				Debug("Connecting " + nameA + " and " + nameB);
			} else {
				Debug("Cannot build a station at " + (siteA ? nameB : nameA));
				throw TaskRetryException();
			}
			
			local exitA = Swap(TerminusStation(siteA, rotA, RAIL_STATION_PLATFORM_LENGTH).GetEntrance());
			local exitB = TerminusStation(siteB, rotB, RAIL_STATION_PLATFORM_LENGTH).GetEntrance();
			
			local network = Network(AIRailTypeList().Begin(), RAIL_STATION_PLATFORM_LENGTH, MIN_TOWN_DISTANCE, MAX_TOWN_DISTANCE);
			subtasks = [
				BuildTerminusStation(siteA, dirA, network, a, false),
				BuildTerminusStation(siteB, dirB, network, b, false),
				BuildTrack(exitA, exitB, [], SignalMode.NONE, network, BuildTrack.FAST),
				BuildBusStations(siteA, a),
				BuildBusStations(siteB, b),
				BuildTrains(siteA, network, PAX, null, true),
				BuildTrains(siteB, network, PAX, null, true),
			];
		}
		
		RunSubtasks();
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
			if (pairs.IsEmpty()) throw TaskFailedException("no suitable towns");
			
			wrapper.append(pairs);
		} else {
			pairs = wrapper[0];
		}
		
		pairs.Valuate(AIBase.RandItem);
		pairs.Sort(AIList.SORT_BY_VALUE, true);
		local pair = pairs.Begin();
		return [pair & 0xFFFF, pair >> 16];
	}
	
}

class BuildCargoLine extends TaskList {
	
	static TILES_PER_DAY = 1;
	static CARGO_STATION_LENGTH = 4;
	
	static bannedCargo = [];
	
	constructor() {
		TaskList.constructor(this, null);
	}
	
	function _tostring() {
		return "BuildCargoLine";
	}
	
	function Run() {
		if (!subtasks) {
			local cargo = SelectCargo();
			Debug("Going to try and build a " + AICargo.GetCargoLabel(cargo) + " line");
			
			local between = SelectIndustries(cargo);
			local a = between[0];
			local b = between[1];
			local locA = AIIndustry.GetLocation(a);
			local locB = AIIndustry.GetLocation(b);
			
			Debug("From " + AIIndustry.GetName(a) + " to " + AIIndustry.GetName(b));
			
			local nameA = AIIndustry.GetName(a);
			local dirA = StationDirection(locA, locB);
			local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
			local siteA = FindIndustryStationSite(a, true, rotA, locB, CARGO_STATION_LENGTH);

			local nameB = AIIndustry.GetName(b);
			local dirB = StationDirection(locB, locA);
			local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
			local siteB = FindIndustryStationSite(b, false, rotB, locA, CARGO_STATION_LENGTH);
			
			if (siteA && siteB) {
				Debug("Connecting " + nameA + " and " + nameB);
			} else {
				Debug("Cannot build a station at " + (siteA ? nameB : nameA));
				throw TaskRetryException();
			}
			
			local exitA = Swap(TerminusStation(siteA, rotA, CARGO_STATION_LENGTH).GetEntrance());
			local exitB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH).GetEntrance();
			
			local network = Network(AIRailTypeList().Begin(), CARGO_STATION_LENGTH, MIN_DISTANCE, MAX_DISTANCE);
			subtasks = [
				BuildTerminusStation(siteA, dirA, network, a, false, CARGO_STATION_LENGTH),
				BuildTerminusStation(siteB, dirB, network, b, false, CARGO_STATION_LENGTH),
				BuildTrack(exitA, exitB, [], SignalMode.NONE, network, BuildTrack.FAST),
				BuildTrains(siteA, network, cargo),
			];
		}
		
		RunSubtasks();
	}
	
	function SelectCargo() {
		local cargoList = AICargoList();
		
		// haven't tried to use it before, and failed
		cargoList.RemoveList(ArrayToList(bannedCargo));
		
		// no passengers, mail or valuables
		foreach (cc in [AICargo.CC_PASSENGERS, AICargo.CC_MAIL, AICargo.CC_EXPRESS, AICargo.CC_ARMOURED]) { 
			cargoList.Valuate(AICargo.HasCargoClass, cc);
			cargoList.KeepValue(0);
		}
		
		// is actually available (primaries only)
		cargoList.Valuate(IsAvailable);
		cargoList.KeepValue(1);
		
		// decent profit
		cargoList.Valuate(AICargo.GetCargoIncome, MAX_DISTANCE, MAX_DISTANCE/TILES_PER_DAY);
		cargoList.KeepTop(5);
		
		if (cargoList.IsEmpty()) {
			throw TaskFailedException("No suitable cargo");
		}
		
		// pick one at random
		cargoList.Valuate(AIBase.RandItem);
		cargoList.KeepTop(1);
		return cargoList.Begin();
	}
	
	/**
	 * See if a cargo is produced anywhere in reasonable quantities.
	 */
	function IsAvailable(cargo) {
		local industries = AIIndustryList_CargoProducing(cargo);
		industries.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		industries.KeepAboveValue(50);
		return !industries.IsEmpty();
	}
	
	function SelectIndustries(cargo) {
		local producers = AIIndustryList_CargoProducing(cargo);
		local consumers = AIIndustryList_CargoAccepting(cargo);
		
		// we want decent production
		producers.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		producers.KeepAboveValue(50);
		
		// and no competition
		producers.Valuate(AIIndustry.GetAmountOfStationsAround);
		producers.KeepValue(0);
		
		// find a random producer/consumer pair that's within our target distance
		producers.Valuate(AIBase.RandItem);
		producers.Sort(AIList.SORT_BY_VALUE, true);
		for (local producer = producers.Begin(); producers.HasNext(); producer = producers.Next()) {
			consumers.Valuate(AIIndustry.GetDistanceManhattanToTile, AIIndustry.GetLocation(producer));
			consumers.KeepAboveValue(MIN_DISTANCE);
			consumers.KeepBelowValue(MAX_DISTANCE);
			if (!consumers.IsEmpty()) {
				return [producer, consumers.Begin()];
			}
		}
		
		// can't find a route for this cargo
		bannedCargo.append(cargo);
		throw TaskRetryException();
	}

}

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
				EstimateNetworkStationCount(tile) >= 2) break;
			
			count++;
			if (count >= MAX_ATTEMPTS) {
				Warning("Tried " + count + " locations to start a new network, map may be full. Trying again tomorrow...");
				throw TaskRetryException(TICKS_PER_DAY);
			}
		}
		
		AIRail.SetCurrentRailType(network.railType);
		tasks.insert(1, TaskList(this, [
			LevelTerrain(tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1]),
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
		MoveConstructionSign(location, this);
		
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

class BuildHQ extends Builder {
	
	constructor(location) {
		Builder.constructor(location);
	}
	
	function _tostring() {
		return "BuildHQ";
	}
	
	function Run() {
		// build our HQ at a four point crossing, if we don't have one yet
		if (HaveHQ()) return;
		
		local crossing = Crossing(location);
		if (crossing.CountConnections() == 4) {
			AICompany.BuildCompanyHQ(GetTile([-1, -1]));
		}
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

class BuildTrack extends Builder {

	// build styles
	static STRAIGHT = 0;
	static LOOSE = 1;
	static FAST = 2;
	
	static SIGNAL_INTERVAL = 3;
	//static DEPOT_INTERVAL = 30;
	static DEPOT_INTERVAL = 0;
	
	a = null;
	b = null;
	c = null;
	d = null;
	ignored = null;
	signalMode = null;
	network = null;
	style = null;
	path = null;
	lastDepot = null;
	
	constructor(from, to, ignored, signalMode, network, style = null) {
		this.a = from[0];
		this.b = from[1];
		this.c = to[0];
		this.d = to[1];
		this.ignored = ignored;
		this.signalMode = signalMode;
		this.network = network;
		this.style = style ? style : STRAIGHT;
		//this.lastDepot = -DEPOT_INTERVAL;	// build one as soon as possible
		this.lastDepot = 0;
		this.path = null;
	}
	
	function _tostring() {
		return "BuildTrack";
	}
	
	function Run() {
		//MoveConstructionSign(a, this);
		
		/*
		AISign.BuildSign(a, "a");
		AISign.BuildSign(b, "b");
		AISign.BuildSign(c, "c");
		AISign.BuildSign(d, "d");
		*/
		
		if (!path) path = FindPath(a, b, c, d, ignored);
		if (!path) throw TaskFailedException("no path");
		BuildPath(path);
	}
	
	function FindPath(a, b, c, d, ignored) {
		local pathfinder = Rail();
		
		local bridgeLength = AIController.GetSetting("MaxBridgeLength");
		pathfinder.cost.max_bridge_length = bridgeLength;
		pathfinder.cost.max_tunnel_length = 5;
		pathfinder.estimate_multiplier = AIController.GetSetting("PathfinderMultiplier");
		
		pathfinder.cost.max_cost = pathfinder.cost.tile * 4 * AIMap.DistanceManhattan(a, d);
		
		if (style == STRAIGHT) {
			pathfinder.cost.diagonal_tile = 200;
		} else if (style == LOOSE) {
			pathfinder.cost.diagonal_tile = 40;
			pathfinder.cost.turn = 25;
			pathfinder.cost.slope = 300;
		} else {
			pathfinder.cost.diagonal_tile = 70;
		}
		
		// high multiplier settings make it very bridge happy, so increase the cost
		pathfinder.cost.bridge_per_tile = 200 + (200 * pathfinder.estimate_multiplier);
		pathfinder.cost.tunnel_per_tile = 100;
		
		// Pathfinding needs money since it attempts to build in test mode.
		// We can't get the price of a tunnel, but we can get it for a bridge
		// and we'll assume they're comparable.
		local maxBridgeCost = GetMaxBridgeCost(pathfinder.cost.max_bridge_length);
		if (GetBankBalance() < maxBridgeCost*2) {
			throw NeedMoneyException(maxBridgeCost*2);
		}
		
		Debug("Pathfinding...");
		pathfinder.InitializePath([[b, a]], [[c, d]], ignored);
		return pathfinder.FindPath(AIMap.DistanceManhattan(a, d) * 3 * TICKS_PER_DAY);
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
		local count = 1;	// don't start with signals right away
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
					
					local possibleDepot = DEPOT_INTERVAL > 0 && prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), forward, true) : null;
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
					
					count++;
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
	function GetDepotSite(prevprev, prev, tile, next, nextnext, forward, checkBuildable) {
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
		
		return (depotSite && (!checkBuildable || AITile.IsBuildable(depotSite))) ? depotSite : null; 
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
	
	function Failed() {
		if (path == false) {
			// no path found
			return;
		}
		
		Debug("Removing...");
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		while (node != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, node.GetTile()) > 1) {
					// bridge or tunnel
					AITile.DemolishTile(prev);
					prevprev = prev;
					prev = node.GetTile();
					node = node.GetParent();
				} else {
					AIRail.RemoveRail(prevprev, prev, node.GetTile());
					local possibleDepot = prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), signalMode == SignalMode.FORWARD, false) : null;
					if (depotSite && AIRail.IsRailDepotTile(depotSite)) {
						AITile.DemolishTile(depotSite);
						AIRail.RemoveRail(depotSite, prev, prevprev);
						AIRail.RemoveRail(depotSite, prev, node.GetTile());
					}
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
		MoveConstructionSign(crossingTile, this);
		
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
		MoveConstructionSign(fromCrossingTile, this);
		
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
	
	function Swap(tiles) {
		return [tiles[1], tiles[0]];
	}
	
	function _tostring() {
		return "ConnectCrossing " + Crossing(fromCrossingTile) + " " + DirectionName(fromDirection) + " to " + Crossing(toCrossingTile);
	}
}

class ExtendCrossing extends TaskList {

	crossing = null;
	direction = null;
	network = null;
	cancelled = null;
	
	constructor(crossing, direction, network) {
		TaskList.constructor(this, null);
		this.crossing = crossing;
		this.direction = direction;
		this.network = network;
		this.cancelled = false;
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
			MoveConstructionSign(crossing, this);
			local towns = FindTowns();
			local town = null;
			local stationTile = null;
			local stationRotation = BuildTerminusStation.StationRotationForDirection(direction);
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
					LevelTerrain(stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2]),
					AppeaseLocalAuthority(town),
					BuildTerminusStation(stationTile, direction, network, town),
					LevelTerrain(crossingTile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1]),
					BuildCrossing(crossingTile, network),
					ConnectCrossing(crossing, direction, crossingTile, crossingEntranceDirection, network),
					ConnectStation(crossingTile, crossingExitDirection, stationTile, network),
					AppeaseLocalAuthority(town),
					BuildBusStations(stationTile, town),
					BuildTrains(stationTile, network, PAX),
				];
			} else {
				subtasks = [
					LevelTerrain(stationTile, stationRotation, [0, 0], [RAIL_STATION_WIDTH-1, RAIL_STATION_LENGTH-2]),
					AppeaseLocalAuthority(town),
					BuildTerminusStation(stationTile, direction, network, town),
					ConnectStation(crossing, direction, stationTile, network),
					AppeaseLocalAuthority(town),
					BuildBusStations(stationTile, town),
					BuildTrains(stationTile, network, PAX),
				];
			}
		}
		
		RunSubtasks();
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

class AppeaseLocalAuthority extends Task {
	
	town = null;
	
	constructor(town) {
		this.town = town;
	}
	
	function _tostring() {
		return "AppeaseLocalAuthority";
	}
	
	function Run() {
		local location = AITown.GetLocation(town);
		MoveConstructionSign(location, this);
		
		local area = AITileList();
		SafeAddRectangle(area, location, 20);
		area.Valuate(AITile.IsWithinTownInfluence, town);
		area.KeepValue(1);
		area.Valuate(AITile.IsBuildable);
		area.KeepValue(1);
		
		local rating = AITown.GetRating(town, COMPANY);
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			if (rating > -200) {
				break;
			}
			
			AITile.PlantTree(tile);
			if (AIError.GetLastError() == AIError.ERR_UNKNOWN) {
				// too many trees on tile, continue
			} else {
				CheckError();
			}
		}
	}
}

class BuildTrains extends TaskList {
	
	static TRAINS_ADDED_PER_STATION = 4;
	
	stationTile = null;
	network = null;
	cargo = null;
	flags = null;
	cheap = null;
	depot = null;
	engine = null;
	
	constructor(stationTile, network, cargo, flags = null, cheap = false) {
		TaskList.constructor(this, null);
		this.stationTile = stationTile;
		this.network = network;
		this.cargo = cargo;
		this.flags = flags == null ? AIOrder.AIOF_NONE : flags;
		this.cheap = cheap;
	}
	
	function _tostring() {
		return "BuildTrains";
	}
	
	function Run() {
		if (!subtasks) {
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
			MoveConstructionSign(depot, this);
			
			// add trains to the N stations with the greatest capacity deficit
			local stationList = ArrayToList(network.stations);
			stationList.RemoveItem(from);
			stationList.Valuate(StationCapacityDeficit);
			stationList.KeepTop(TRAINS_ADDED_PER_STATION);
			
			subtasks = [];
			for (local to = stationList.Begin(); stationList.HasNext(); to = stationList.Next()) {
				// the first train always gets a full load order to boost ratings
				local first = subtasks.len() == 0;
				local fromFlags = first ? flags | AIOrder.AIOF_FULL_LOAD_ANY : flags;
				local toFlags = flags;
				subtasks.append(BuildTrain(from, to, depot, network, fromFlags, toFlags, cargo));
			}
		}
		
		RunSubtasks();
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
	
	static bannedEngines = [];
	
	from = null;
	to = null;
	depot = null;
	network = null;
	cheap = null;
	fromFlags = null;
	toFlags = null;
	cargo = null;
	train = null;
	hasMail = null;
	
	constructor(from, to, depot, network, fromFlags, toFlags, cargo = null, cheap = false) {
		this.from = from;
		this.to = to;
		this.depot = depot;
		this.network = network;
		this.fromFlags = fromFlags;
		this.toFlags = toFlags;
		this.cargo = cargo ? cargo : PAX;
		this.cheap = cheap;
		this.train = null;
		this.hasMail = false;
	}
	
	function _tostring() {
		return "BuildTrain from " + AIStation.GetName(from) + " to " + AIStation.GetName(to) + " at " + TileToString(depot);
	}
	
	function Run() {
		// we need an engine
		if (!train || !AIVehicle.IsValidVehicle(train)) {
			//Debug("Building locomotive at " + AIMap.GetTileX(depot) + "," + AIMap.GetTileY(depot));
			local engineType = GetEngine(network.railType, cheap);
			train = AIVehicle.BuildVehicle(depot, engineType);
			
			// locomotives are expensive compared to other things we build
			if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
				throw NeedMoneyException(AIEngine.GetPrice(engineType));
			}
			
			CheckError();
		}
		
		if (cargo == PAX) {
			// include one mail wagon
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
		}
		
		
		// and fill the rest of the train with passenger wagons
		local wagonType = GetWagon(cargo, network.railType);
		while (TrainLength(train) <= network.trainLength) {
			local wagon = AIVehicle.BuildVehicle(depot, wagonType);
			CheckError();
			
			AIVehicle.RefitVehicle(wagon, cargo);
			CheckError();
			
			if (!AIVehicle.MoveWagon(wagon, 0, train, 0)) {
				// can't add passenger wagons to this type of engine, so don't build it again
				bannedEngines.append(AIVehicle.GetEngineType(train));
				
				// sell it and try again
				AIVehicle.SellVehicle(train);
				AIVehicle.SellVehicle(wagon);
				train = null;
				throw TaskRetryException();
			}
		}
		
		// see if we went over - newgrfs can introduce non-half-tile wagons
		while (TrainLength(train) > network.trainLength) {
			AIVehicle.SellWagon(train, 1);
		}

		network.trains.append(train);
		AIOrder.AppendOrder(train, AIStation.GetLocation(from), fromFlags);
		AIOrder.AppendOrder(train, AIStation.GetLocation(to), toFlags);
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
		
		if (engineList.IsEmpty()) throw TaskFailedException("no suitable engine");
		return engineList.Begin();
	}
	
	function GetWagon(cargoID, railType) {
		// select the largest appropriate wagon type
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.CanRefitCargo, cargoID);
		engineList.KeepValue(1);

		engineList.Valuate(AIEngine.IsWagon);
		engineList.KeepValue(1);
		
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		
		// prefer engines that can carry this cargo without a refit,
		// because their refitted capacity may be different from
		// their "native" capacity - for example, NARS Ore Hoppers
		local native = AIList();
		native.AddList(engineList);
		native.Valuate(AIEngine.GetCargoType);
		native.KeepValue(cargoID);
		if (!native.IsEmpty()) {
			engineList = native;
		}
		
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
		MoveConstructionSign(location, this);
		
		local tiles = AITileList();
		tiles.AddRectangle(GetTile(from), GetTile(to));
		
		local min = 100;
		local max = 0;
		
		for (local tile = tiles.Begin(); tiles.HasNext(); tile = tiles.Next()) {
			if (AITile.GetMaxHeight(tile) > max) max = AITile.GetMaxHeight(tile);
			if (AITile.GetMinHeight(tile) < min) min = AITile.GetMinHeight(tile);
		}
		
		// prefer rounding down - cheaper when we're near the sea
		local targetHeight = (min + max) / 2;
		for (local tile = tiles.Begin(); tiles.HasNext(); tile = tiles.Next()) {
			LevelTile(tile, targetHeight);
		}
			
		// TODO: this levels the area between the north corners of the resulting tiles
		// so due to rotation, we may be one tile short
		//AITile.LevelTiles(GetTile(from), GetTile(to));
		//CheckError();
	}
	
	function LevelTile(tile, height) {
		// raise or lower each corner of the tile to the target height
		foreach (corner in [AITile.CORNER_N, AITile.CORNER_E, AITile.CORNER_S, AITile.CORNER_W]) {
			while (AITile.GetCornerHeight(tile, corner) < height) {
				AITile.RaiseTile(tile, 1 << corner);
				CheckTerraformingError();
			}
			
			while (AITile.GetCornerHeight(tile, corner) > height) {
				AITile.LowerTile(tile, 1 << corner);
				CheckTerraformingError();
			}
		}
	}
	
	function CheckTerraformingError() {
		switch (AIError.GetLastError()) {
			case AIError.ERR_NONE:
				// all's well
				break;
			case AIError.ERR_NOT_ENOUGH_CASH:
				// normal error handling: wait for money and retry
				CheckError();
				break;
			default:
				// we can't level the terrain as requested,
				// but because of foundations built on slopes,
				// we may be able to continue, so don't abort yet
				break;
		}
	}
	
	function _tostring() {
		return "LevelTerrain";
	}
	
}

function Swap(tiles) {
	return [tiles[1], tiles[0]];
}

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
	flat.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], true);
	flat.KeepValue(1);
	
	if (flat.Count() > 0) {
		area = flat;
	} else {
		// try again, with terraforming
		area.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, RAIL_STATION_LENGTH], false);
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

/**
 * Find a site for a station at the given town.
 */
function FindIndustryStationSite(industry, producing, stationRotation, destination, platformLength) {
	local location = AIIndustry.GetLocation(industry);
	local area = producing ? AITileList_IndustryProducing(industry, RAIL_STATION_RADIUS) : AITileList_IndustryAccepting(industry, RAIL_STATION_RADIUS);
	
	// room for a station
	area.Valuate(IsBuildableRectangle, stationRotation, [0, 0], [RAIL_STATION_WIDTH, platformLength + 3], true);
	area.KeepValue(1);
	
	// pick the tile farthest from the destination for increased profit
	//area.Valuate(AITile.GetDistanceManhattanToTile, destination);
	//area.KeepTop(1);
	
	// pick the tile closest to the industry for looks
	area.Valuate(AITile.GetDistanceManhattanToTile, location);
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
				abs(AITile.GetHeight(tile) - height) <= 1 &&
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

function MoveConstructionSign(tile, task) {
	AISign.RemoveSign(SIGN);
	
	if (!AIController.GetSetting("ActivitySigns")) return;
	
	local text = task.tostring();
	local space = text.find(" ");
	if (space) {
		text = text.slice(0, space);
	}
	
	text = "ChooChoo: " + text;
	
	if (text.len() > 30) {
		text = text.slice(0, 29);
	}
	
	SIGN = AISign.BuildSign(tile, text);
}
