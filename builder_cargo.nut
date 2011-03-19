class BuildCargoLine extends Task {
	
	static CARGO_MIN_DISTANCE = 30;
	static CARGO_MAX_DISTANCE = 75;
	static TILES_PER_DAY = 1;
	static CARGO_STATION_LENGTH = 3;
	
	static bannedCargo = [];
	static routes = [];
	
	constructor(parentTask=null) {
		Task.constructor(parentTask, null);
	}
	
	function _tostring() {
		return "BuildCargoLine";
	}
	
	function Run() {
		if (routes.len() == 0) {
			Debug("Calculating best cargo routes...");
			routes.extend(CalculateRoutes());
		}
		
		if (!subtasks) {
			/*
			local cargo = SelectCargo();
			local railType = SelectRailType(cargo);
			AIRail.SetCurrentRailType(railType);
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			// Debug("Max distance for " + AICargo.GetCargoLabel(cargo) + ": " + maxDistance);
			
			local between = SelectIndustries(cargo, maxDistance);
			local a = between[0];
			local b = between[1];
			*/

			local route = routes[0];
			routes.remove(0);
			
			local cargo = route.cargo;
			local a = route.from;
			local b = route.to;
			
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			local railType = SelectRailType(cargo);
			AIRail.SetCurrentRailType(railType);
			
			if (AIIndustry.GetAmountOfStationsAround(a) > 0) {
				Debug(AIIndustry.GetName(a), "is already being served");
				throw TaskRetryException();
			}
						
			Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", AIIndustry.GetName(a), "to", AIIndustry.GetName(b));
			
			// [siteA, rotA, dirA, siteB, rotB, dirB]
			local sites = FindStationSites(a, b);
			if (sites == null) {
				Debug("Cannot build both stations");
				throw TaskRetryException();
			}
			
			local siteA = sites[0];
			local rotA = sites[1];
			local dirA = sites[2];
			local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
			
			local siteB = sites[3];
			local rotB = sites[4];
			local dirB = sites[5];
			local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
			
			// double track cargo lines discarded: we just use them for cheap starting income
			// old strategy: build the first track and two trains first, which can then finance the upgrade to double track
			//local reserved = stationA.GetReservedEntranceSpace();
			//reserved.extend(stationB.GetReservedExitSpace());
			//local exitA = Swap(TerminusStation(siteA, rotA, CARGO_STATION_LENGTH).GetEntrance());
			//local exitB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH).GetEntrance();
			//local firstTrack = BuildTrack(stationA.GetExit(), stationB.GetEntrance(), reserved, SignalMode.NONE, network);
			
			local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
			subtasks = [
				// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
				BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH),
				BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH),
				BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
				//firstTrack,
				BuildTrains(this, siteA, network, cargo, AIOrder.AIOF_FULL_LOAD_ANY),
				//BuildTrains(this, siteA, network, cargo, AIOrder.AIOF_FULL_LOAD_ANY),
				//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
				//BuildSignals(this, firstTrack, SignalMode.FORWARD),
			];
		}
		
		RunSubtasks();
	}
	
	function SelectRailType(cargo) {
		// select a rail type for which we can build a locomotive that can pull wagons for the desired cargo
		local railTypes = AIRailTypeList();
		railTypes.Valuate(CarriesCargo, cargo);
		railTypes.KeepValue(1);
		railTypes.Valuate(AIRail.GetBuildCost, AIRail.BT_TRACK);
		railTypes.KeepAboveValue(0);	// filter out NuTracks planning tracks, which are free
		railTypes.KeepBottom(1);		// use the cheap stuff for cargo
		if (railTypes.IsEmpty()) {
			bannedCargo.append(cargo);
			throw TaskFailedException("no rail type for " + AICargo.GetCargoLabel(cargo));
		} else {
			return railTypes.Begin();
		}
	}
	
	function CarriesCargo(railType, cargo) {
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.IsWagon);
		engineList.KeepValue(0);
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.HasPowerOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.CanPullCargo, cargo);
		engineList.KeepValue(1);
		return engineList.IsEmpty() ? 0 : 1;
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
		cargoList.Valuate(AICargo.GetCargoIncome, CARGO_MAX_DISTANCE, CARGO_MAX_DISTANCE/TILES_PER_DAY);
		cargoList.KeepTop(3);
		
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
	
	function SelectIndustries(cargo, maxDistance) {
		local producers = AIIndustryList_CargoProducing(cargo);
		
		// we want decent production
		producers.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		producers.KeepAboveValue(80);
		
		// and no competition, nor an earlier station of our own
		producers.Valuate(AIIndustry.GetAmountOfStationsAround);
		producers.KeepValue(0);
		
		// find a random producer/consumer pair that's within our target distance
		producers.Valuate(AIBase.RandItem);
		producers.Sort(AIList.SORT_BY_VALUE, true);
		for (local producer = producers.Begin(); producers.HasNext(); producer = producers.Next()) {
			local consumers = AIIndustryList_CargoAccepting(cargo);
			consumers.Valuate(AIIndustry.GetDistanceManhattanToTile, AIIndustry.GetLocation(producer));
			consumers.KeepAboveValue(CARGO_MIN_DISTANCE);
			consumers.KeepBelowValue(maxDistance);
			
			for (local consumer = consumers.Begin(); consumers.HasNext(); consumer = consumers.Next()) {
				if (FindStationSites(producer, consumer)) {
					return [producer, consumer];
				}
			}
		}
		
		// can't find a route for this cargo
		Warning("No route for " + AICargo.GetCargoLabel(cargo));
		bannedCargo.append(cargo);
		throw TaskRetryException();
	}
	
	function FindStationSites(a, b) {
		local locA = AIIndustry.GetLocation(a);
		local locB = AIIndustry.GetLocation(b);
		
		local nameA = AIIndustry.GetName(a);
		local dirA = StationDirection(locA, locB);
		local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
		//local siteA = FindIndustryStationSite(a, true, rotA, locB, CARGO_STATION_LENGTH + 3, 2);
		local siteA = FindIndustryStationSite(a, true, rotA, locB);

		local nameB = AIIndustry.GetName(b);
		local dirB = StationDirection(locB, locA);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		//local siteB = FindIndustryStationSite(b, false, rotB, locA, CARGO_STATION_LENGTH + 3, 2);
		local siteB = FindIndustryStationSite(b, false, rotB, locA);
		
		if (siteA && siteB) {
			return [siteA, rotA, dirA, siteB, rotB, dirB];
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return null;
		}
	}
	
	/**
	 * Find a site for a station at the given industry.
	 */
	function FindIndustryStationSite(industry, producing, stationRotation, destination) {
		local location = AIIndustry.GetLocation(industry);
		local area = producing ? AITileList_IndustryProducing(industry, RAIL_STATION_RADIUS) : AITileList_IndustryAccepting(industry, RAIL_STATION_RADIUS);
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.KeepTop(1);
		
		// pick the tile closest to the industry for looks
		//area.Valuate(AITile.GetDistanceManhattanToTile, location);
		//area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
}
