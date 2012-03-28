class BuildTrains extends Task {
	
	static TRAINS_ADDED_PER_STATION = 4;
	
	stationTile = null;
	network = null;
	cargo = null;
	fromFlags = null;
	toFlags = null;
	cheap = null;
	engine = null;
	
	constructor(parentTask, stationTile, network, cargo, fromFlags = null, toFlags = null, cheap = false) {
		Task.constructor(parentTask);
		this.stationTile = stationTile;
		this.network = network;
		this.cargo = cargo;
		this.fromFlags = fromFlags == null ? AIOrder.AIOF_NONE : fromFlags;
		this.toFlags = toFlags == null ? AIOrder.AIOF_NONE : toFlags;
		this.cheap = cheap;
	}
	
	function _tostring() {
		return "BuildTrains";
	}
	
	function Run() {
		if (!subtasks) {
			local from = AIStation.GetStationID(stationTile);
			local fromDepot = ClosestDepot(from);
			SetConstructionSign(fromDepot, this);
			
			// add trains to the N stations with the greatest capacity deficit
			local stationList = ArrayToList(network.stations);
			stationList.RemoveItem(from);
			stationList.Valuate(StationCapacityDeficit);
			stationList.KeepTop(TRAINS_ADDED_PER_STATION);
			
			subtasks = [];
			for (local to = stationList.Begin(); stationList.HasNext(); to = stationList.Next()) {
				local toDepot = ClosestDepot(to);
				subtasks.append(BuildTrain(from, to, fromDepot, toDepot, network, fromFlags, toFlags, cargo));
			}
		}
		
		RunSubtasks();
	}
	
	function ClosestDepot(station) {
		local depotList = AIList();
		foreach (depot in network.depots) {
			depotList.AddItem(depot, 0);
		}
		
		depotList.Valuate(AIMap.DistanceManhattan, AIStation.GetLocation(station));
		depotList.KeepBottom(1);
		return depotList.IsEmpty() ? null : depotList.Begin();
	}
	
	/**
	 * Calculates the difference between the amount of cargo/passengers produced
	 * and the transport capacity of currently assigned trains.
	 */
	function StationCapacityDeficit(station) {
		local production = AITown.GetLastMonthProduction(AIStation.GetNearestTown(station), PAX);
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
	fromDepot = null;
	toDepot = null;
	network = null;
	cheap = null;
	fromFlags = null;
	toFlags = null;
	cargo = null;
	train = null;
	hasMail = null;
	
	constructor(from, to, fromDepot, toDepot, network, fromFlags, toFlags, cargo = null, cheap = false) {
		this.from = from;
		this.to = to;
		this.fromDepot = fromDepot;
		this.toDepot = toDepot;
		this.network = network;
		this.fromFlags = fromFlags;
		this.toFlags = toFlags;
		this.cargo = cargo ? cargo : PAX;
		this.cheap = cheap;
		this.train = null;
		this.hasMail = false;
	}
	
	function _tostring() {
		return "BuildTrain from " + AIStation.GetName(from) + " to " + AIStation.GetName(to) + " at " + TileToString(fromDepot);
	}
	
	function Run() {
		// there appears to be a bug
		if (!AIStation.IsValidStation(from) || !AIStation.IsValidStation(to)) {
			throw TaskFailedException("Invalid route: " + this);
		}
		
		// we need an engine
		if (!train || !AIVehicle.IsValidVehicle(train)) {
			local engineType = GetEngine(cargo, network.railType, bannedEngines, cheap);
			
			// don't try building the train until we (probably) have enough
			// for the wagons as well, or it may sit in a depot for ages
			CheckFunds(engineType);
			
			train = AIVehicle.BuildVehicle(fromDepot, engineType);
			CheckError();
		}
		
		if (cargo == PAX) {
			// include one mail wagon
			if (!hasMail) {
				local wagonType = GetWagon(MAIL, network.railType);
				if (wagonType) {
					local wagon = AIVehicle.BuildVehicle(fromDepot, wagonType);
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
			local wagon = AIVehicle.BuildVehicle(fromDepot, wagonType);
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

		// the first train for a station gets a full load order to boost ratings
		//local first = AIVehicleList_Station(from).Count() == 0;
		//fromFlags = first ? fromFlags | AIOrder.AIOF_FULL_LOAD_ANY : fromFlags;
		
		network.trains.append(train);
		AIOrder.AppendOrder(train, AIStation.GetLocation(from), fromFlags);
		AIOrder.AppendOrder(train, fromDepot, AIOrder.AIOF_SERVICE_IF_NEEDED);
		AIOrder.AppendOrder(train, AIStation.GetLocation(to), toFlags);
		AIOrder.AppendOrder(train, toDepot, AIOrder.AIOF_SERVICE_IF_NEEDED);
		AIVehicle.StartStopVehicle(train);
	}
	
	function CheckFunds(engineType) {
		// assume half tile wagons
		local wagonType = GetWagon(cargo, network.railType);
		local numWagons = network.trainLength * 2;
		local estimate = AIEngine.GetPrice(engineType) + numWagons * AIEngine.GetPrice(wagonType);
		if (GetBankBalance() < estimate) {
			throw NeedMoneyException(estimate);
		}
	}
}
