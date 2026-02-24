function ClosestDepot(network, stationID) {
	// TODO should we instead find the depot from the station layout?
	// Technically this does not guarantee the depot is reachable
	local depotList = AIList();
	foreach (depot in network.depots) {
		depotList.AddItem(depot, 0);
	}
	
	depotList.Valuate(AIMap.DistanceManhattan, AIStation.GetLocation(stationID));
	depotList.KeepBottom(1);
	return depotList.IsEmpty() ? null : depotList.Begin();
}

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
			local fromDepot = ClosestDepot(network, from);
			SetConstructionSign(fromDepot, this);
			
			// add trains to the N stations with the greatest capacity deficit
			local stationList = ArrayToList(network.stations);
			stationList.RemoveItem(from);
			stationList.Valuate(StationCapacityDeficit);
			stationList.KeepTop(TRAINS_ADDED_PER_STATION);
			
			subtasks = [];
			for (local to = stationList.Begin(); stationList.HasNext(); to = stationList.Next()) {
				local toDepot = ClosestDepot(network, to);
				subtasks.append(AddTrain(this, from, to, fromDepot, toDepot, network, network.trainLength, fromFlags, toFlags, cargo));
			}
		}
		
		RunSubtasks();
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

class BuildBranchTrain extends Task {
	mainlineStationTile = null;
	branchStationTile = null;
	network = null;
	cargo = null;
	fromFlags = null;
	toFlags = null;
	cheap = null;
	engine = null;
	
	constructor(parentTask, mainlineStationTile, branchStationTile, network, cargo, fromFlags = null, toFlags = null, cheap = false) {
		Task.constructor(parentTask);
		this.mainlineStationTile = mainlineStationTile;
		this.branchStationTile = branchStationTile;
		this.network = network;
		this.cargo = cargo;
		this.fromFlags = fromFlags == null ? AIOrder.AIOF_NONE : fromFlags;
		this.toFlags = toFlags == null ? AIOrder.AIOF_NONE : toFlags;
		this.cheap = cheap;
	}
	
	function _tostring() {
		return "BuildBranchTrain";
	}
	
	function Run() {
		local from = AIStation.GetStationID(mainlineStationTile);
		local to = AIStation.GetStationID(branchStationTile);
		local fromDepot = ClosestDepot(network, from);

		if (!subtasks) {
			SetConstructionSign(fromDepot, this);
			subtasks = [AddTrain(this, from, to, fromDepot, null, network, network.trainLength - 1, fromFlags, toFlags, cargo)];
		}
		
		RunSubtasks();

		// encode "branch" status in name so we can skip it during cloning
		local train = completed[0].train;
		GenerateName(train, fromDepot, "B");
	}
}

class AddTrain extends Task {
	
	static bannedEngines = [];
	
	from = null;
	to = null;
	fromDepot = null;
	toDepot = null;
	network = null;
	trainLength = null;
	cheap = null;
	fromFlags = null;
	toFlags = null;
	cargo = null;
	train = null;
	hasMail = null;
	
	constructor(parentTask, from, to, fromDepot, toDepot, network, trainLength, fromFlags, toFlags, cargo = null, cheap = false) {
		Task.constructor(parentTask);
		this.from = from;
		this.to = to;
		this.fromDepot = fromDepot;
		this.toDepot = toDepot;
		this.network = network;
		this.trainLength = trainLength;
		this.fromFlags = fromFlags;
		this.toFlags = toFlags;
		this.cargo = cargo ? cargo : PAX;
		this.cheap = cheap;
		this.train = null;
	}
	
	function _tostring() {
		return "AddTrain from " + AIStation.GetName(from) + " to " + AIStation.GetName(to) + " at " + TileToString(fromDepot);
	}
	
	function Run() {
		// there appears to be a bug
		if (!AIStation.IsValidStation(from) || !AIStation.IsValidStation(to)) {
			throw TaskFailedException("Invalid route: " + this);
		}

		if (!subtasks) {
			subtasks = [BuildTrain(this, fromDepot, trainLength, cargo, cheap)]
		}

		RunSubtasks();

		train = completed[0].train;
		network.trains.append(train);
		AIOrder.AppendOrder(train, AIStation.GetLocation(from), fromFlags);
		AIOrder.AppendOrder(train, fromDepot, AIOrder.AIOF_SERVICE_IF_NEEDED);
		AIOrder.AppendOrder(train, AIStation.GetLocation(to), toFlags);
		if (toDepot != null) {
			AIOrder.AppendOrder(train, toDepot, AIOrder.AIOF_SERVICE_IF_NEEDED);
		}
		AIVehicle.StartStopVehicle(train);
	}
}

class ReplaceTrain extends Task {
	train = null;
	depot = null;
	cargo = null;

	constructor(parentTask, train) {
		Task.constructor(parentTask);
		this.train = train;
	}

	function _tostring() {
		return "ReplaceTrain " + AIVehicle.GetName(train);
	}

	function Run() {
		if (!AIVehicle.IsValidVehicle(train)) {
			throw TaskFailedException("Train no longer exists");
		}

		local name = AIVehicle.GetName(train);
		depot = GetDepot(train);
		local railType = AIRail.GetRailType(depot);
		local trainLength = TrainLength(train);

		// determine cargo: use the largest capacity cargo
		cargo = AIVehicle.GetCapacity(train, PAX) > 0 ? PAX : null;
		if (cargo == null) {
			local cargoList = AICargoList();
			local bestCargo = -1;
			local bestCapacity = 0;
			for (local c = cargoList.Begin(); cargoList.HasNext(); c = cargoList.Next()) {
				local cap = AIVehicle.GetCapacity(train, c);
				if (cap > bestCapacity) {
					bestCapacity = cap;
					bestCargo = c;
				}
			}
			cargo = bestCargo;
		}

		if (cargo == null || cargo == -1) {
			throw TaskFailedException("Cannot determine cargo for " + name);
		}

		if (!subtasks) {
			subtasks = [BuildTrain(this, depot, trainLength, cargo, false)];
		}

		RunSubtasks();

		// copy orders from old train (shared)
		local newTrain = completed[0].train;
		AIOrder.ShareOrders(newTrain, train);

		// name the new train with the same depot encoding
		local prefix = IsBranchLineTrain(train) ? "B" : "T";
		GenerateName(newTrain, depot, prefix);

		// start the new train
		// this should be safe to do before the old one is gone:
		// - main lines support multiple trains on a route
		// - cargo lines have no signals so the new train will wait in the depot for the track to clear
		// - branch lines have no depots and no signals, so the new train will wait for the branch to be empty
		AIVehicle.StartStopVehicle(newTrain);

		// send old train to depot for selling
		Cull(train);
	}
}

class BuildTrain extends Task {
	
	static bannedEngines = [];
	
	depot = null;
	cargo = null;
	maxLength = null;
	cheap = null;
	railType = null;
	train = null;
	hasMail = null;
	
	constructor(parentTask, depot, maxLength, cargo = null, cheap = false) {
		Task.constructor(parentTask);
		this.depot = depot;
		this.maxLength = maxLength;
		this.cargo = cargo ? cargo : PAX;
		this.cheap = cheap;
		this.railType = AIRail.GetRailType(depot);
		this.train = null;
		this.hasMail = false;
	}
	
	function _tostring() {
		return "BuildTrain for " + AICargo.GetCargoLabel(cargo) + " at " + TileToString(depot);
	}
	
	function Run() {
		// we need an engine
		if (!train || !AIVehicle.IsValidVehicle(train)) {
			local engineType = GetEngine(cargo, railType, bannedEngines, cheap);
			
			// don't try building the train until we (probably) have enough
			// for the wagons as well, or it may sit in a depot for ages
			CheckFunds(engineType);

			train = AIVehicle.BuildVehicle(depot, engineType);
			CheckError();

			// TODO check for ERR_VEHICLE_TOO_MANY and stop building routes
			// and/or initiate culling
		}
		
		if (cargo == PAX && MAIL != null) {
			// include one mail wagon
			if (!hasMail) {
				local wagonType = GetWagon(MAIL, railType);
				if (wagonType) {
					local wagon = AIVehicle.BuildVehicle(depot, wagonType);
					CheckError();
					if (!AIVehicle.MoveWagon(wagon, 0, train, 0)) {
						// can't add mail wagon to engine, sell it
						// may mean passengers don't work either, which will
						// ban this engine type
						AIVehicle.SellVehicle(wagon);
					}
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
		local wagonType = GetWagon(cargo, railType);
		while (TrainLength(train) <= maxLength) {
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
		while (TrainLength(train) > maxLength) {
			AIVehicle.SellWagon(train, 1);
		}

		GenerateName(train, depot);
	}
	
	function CheckFunds(engineType) {
		// assume half tile wagons
		local wagonType = GetWagon(cargo, railType);
		local numWagons = maxLength * 2;
		local estimate = AIEngine.GetPrice(engineType) + numWagons * AIEngine.GetPrice(wagonType);
		if (GetBankBalance() < estimate) {
			throw NeedMoneyException(estimate);
		}
	}
}
