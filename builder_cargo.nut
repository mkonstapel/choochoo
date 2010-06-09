class BuildCargoLine extends TaskList {
	
	static CARGO_MIN_DISTANCE = 30;
	static CARGO_MAX_DISTANCE = 150;
	static TILES_PER_DAY = 1;
	static CARGO_STATION_LENGTH = 5;
	
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
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			Debug("Max distance for " + AICargo.GetCargoLabel(cargo) + ": " + maxDistance);
			
			local between = SelectIndustries(cargo, maxDistance);
			local a = between[0];
			local b = between[1];
			Debug(AICargo.GetCargoLabel(cargo) + " from " + AIIndustry.GetName(a) + " to " + AIIndustry.GetName(b));
			
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
			
			local network = Network(AIRailTypeList().Begin(), CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
			subtasks = [
				// build the track first - if we don't find a path, we don't lose any money
				BuildTrack(Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
				BuildCargoStation(siteA, dirA, network, a, CARGO_STATION_LENGTH),
				BuildCargoStation(siteB, dirB, network, b, CARGO_STATION_LENGTH),
				//firstTrack,
				BuildTrains(siteA, network, cargo, AIOrder.AIOF_FULL_LOAD_ANY),
				//BuildTrains(siteA, network, cargo, AIOrder.AIOF_FULL_LOAD_ANY),
				//BuildTrack(Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
				//BuildSignals(firstTrack, SignalMode.FORWARD),
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
		producers.KeepAboveValue(50);
		
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
		local siteA = FindIndustryStationSite(a, true, rotA, locB, CARGO_STATION_LENGTH + 1, 2);

		local nameB = AIIndustry.GetName(b);
		local dirB = StationDirection(locB, locA);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		local siteB = FindIndustryStationSite(b, false, rotB, locA, CARGO_STATION_LENGTH + 1, 2);
		
		if (siteA && siteB) {
			return [siteA, rotA, dirA, siteB, rotB, dirB];
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return null;
		}
	}

}
