// dumped here in case it turns out to be useful

class BuildLine extends Task {
	
	static MIN_TOWN_POPULATION = 500;
	static MIN_TOWN_DISTANCE = 30;
	static MAX_TOWN_DISTANCE = 100;
	
	static wrapper = [];
	
	constructor(parentTask) {
		Task.constructor(parentTask);
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
			local rotA = StationRotationForDirection(dirA);
			local siteA = FindStationSite(a, rotA, AITown.GetLocation(b));
	
			local nameB = AITown.GetName(b);
			local locB = AITown.GetLocation(b);
			local dirB = StationDirection(AITown.GetLocation(b), AITown.GetLocation(a));
			local rotB = StationRotationForDirection(dirB);
			local siteB = FindStationSite(b, rotB, AITown.GetLocation(a));
			
			if (siteA && siteB) {
				Debug("Connecting " + nameA + " and " + nameB);
			} else {
				Debug("Cannot build a station at " + (siteA ? nameB : nameA));
				throw TaskRetryException();
			}
			
			local exitA = Swap(TerminusStation(siteA, rotA, RAIL_STATION_PLATFORM_LENGTH).GetEntrance());
			local exitB = TerminusStation(siteB, rotB, RAIL_STATION_PLATFORM_LENGTH).GetEntrance();
			
			local network = Network(AIRailTypeList().Begin(), IsRightHandTraffic(), RAIL_STATION_PLATFORM_LENGTH, MIN_TOWN_DISTANCE, MAX_TOWN_DISTANCE);
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

class BuildTruckRoute extends Task {
	
	static MIN_DISTANCE = 20;
	static MAX_DISTANCE = 100;
	static TILES_PER_DAY = 1;
	static TRUCK_STATION_RADIUS = 3;
	
	static bannedCargo = [];
	
	function Run() {
		local cargo = SelectCargo();
		Debug("Going to try and build a " + AICargo.GetCargoLabel(cargo) + " route");
		
		local between = SelectIndustries(cargo);
		local producer = between[0];
		local consumer = between[1];
		Debug("From " + AIIndustry.GetName(producer) + " to " + AIIndustry.GetName(consumer));
		
		Connect(producer, consumer);
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
		cargoList.KeepTop(3);
		
		if (cargoList.IsEmpty()) {
			throw TaskFailedException("no suitable cargo");
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
	
	function Connect(fromIndustry, toIndustry) {
		local fromArea = KeepBuildableArea(AITileList_IndustryProducing(fromIndustry, TRUCK_STATION_RADIUS));
		local toArea = KeepBuildableArea(AITileList_IndustryAccepting(toIndustry, TRUCK_STATION_RADIUS));
		local path = FindPath(ListToArray(fromArea), ListToArray(toArea));
		if (path) {
			BuildRoadPath(path);
			BuildTruckStation(StartOfPath(path));
			BuildTruckStation(EndOfPath(path));
			BuildDepot(path);
		} else {
			throw TaskFailedException("no path");
		}
	}
	
	/**
	 * Return a RoadPathFinder path, or null if no path was found.
	 */
	function FindPath(startTiles, endTiles) {
		local pathfinder = RoadPathFinder();
		// TODO: update to v4
		// pathfinder.cost.estimate_multiplier = 2;
		pathfinder.InitializePath(startTiles, endTiles);
		
		Debug("Pathfinding...");
		// TODO: restrict max. time
		return pathfinder.FindPath(-1);
	}
	
	function BuildRoadPath(path) {
		Debug("Building road...");
		while (path != null) {
			local par = path.GetParent();
			if (par != null) {
				local last_node = path.GetTile();
				if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
					AIRoad.BuildRoad(path.GetTile(), par.GetTile());
					CheckError();
				} else {
					/* Build a bridge or tunnel. */
					if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
						/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
						if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
						if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
							AITunnel.BuildTunnel(AIVehicle.VEHICLE_ROAD, path.GetTile());
							CheckError();
						} else {
							local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
							bridge_list.Valuate(AIBridge.GetMaxSpeed);
							bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);
							AIBridge.BuildBridge(AIVehicle.VEHICLE_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile());
							CheckError();
						}
					}
				}
			}
			path = par;
		}
	}
	
	function BuildDepot(path) {
		throw TaskFailedException("not implemented");
	}
	
	function BuildTruckStation(tiles) {
		AIRoad.BuildDriveThroughRoadStation(tiles[0], tiles[1], AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW);
		CheckError();
	}
}

