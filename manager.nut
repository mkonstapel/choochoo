/**
 * Clone the top 10%, cull the bottom 10%, replace old vehicles.
 */
function ManageVehicles() {
	// clone the top 10%, and cull the bottom 10%
	Debug("Culling the herd...");
	local trains = AIVehicleList();
	trains.Valuate(AIVehicle.GetVehicleType);
	trains.KeepValue(AIVehicle.VT_RAIL);
	Debug(trains.Count() + " trains");
	trains.Valuate(AIVehicle.GetAge);
	trains.KeepAboveValue(2*365);
	Debug(trains.Count() + " trains older than 2");
	trains.Valuate(AIVehicle.GetCapacity, PAX);
	trains.KeepAboveValue(0);
	Debug(trains.Count() + " trains carrying PAX");
	// don't clone trains on branch lines, that'll deadlock
	// and don't delete them, because each branch only has one train servicing it
	trains.Valuate(IsBranchLineTrain);
	trains.KeepValue(0);
	Debug(trains.Count() + " mainline trains");

	trains.Valuate(AIVehicle.GetProfitLastYear);
	local n = trains.Count();
	local best = AIList();
	local worst = AIList();
	best.AddList(trains);
	worst.AddList(trains);

	best.KeepTop(n/10);
	
	// TODO don't delete trains that are the only one servicing a station
	// see AIVehicleList_Station
	worst.Valuate(IsOnlyTrainServicingStation);
	worst.KeepValue(0);
	worst.Valuate(AIVehicle.GetProfitLastYear);
	worst.KeepBottom(n/10);

	local clones = 0;
	foreach (train, profit in best) {
		Debug("Cloning " + AIVehicle.GetName(train) + ", made " + profit + " last year");
		local copy = Clone(train);
		if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
			// if we don't have the money to clone the current best one,
			// don't bother with the rest of the list
			break;
		}

		if (AIVehicle.IsValidVehicle(copy)) {
			AIVehicle.StartStopVehicle(copy);
			clones++;
		}
	}
	
	foreach (train, profit in worst) {
		Debug("Culling " + AIVehicle.GetName(train) + ", made " + profit + " last year");
		Cull(train);
		clones--;
		// don't remove more than we add
		if (clones <= 0)
			break;
	}
	
	// replace aging trains and buses
	local vehicles = AIVehicleList();
	vehicles.Valuate(AIVehicle.GetAgeLeft);
	vehicles.KeepBelowValue(365);

	for (local vehicle = vehicles.Begin(); vehicles.HasNext(); vehicle = vehicles.Next()) {
		local name = AIVehicle.GetName(vehicle);
		// skip already-marked vehicles (R or X prefix)
		if (name == null || name.find("R") == 0 || name.find("X") == 0) continue;

		Debug("Replacing aging vehicle: " + name);
		AIVehicle.SetName(vehicle, "R" + name);

		local task = AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_RAIL ? ReplaceTrain(null, vehicle) : ReplaceBus(null, vehicle);
		tasks.insert(1, task);
	}

	Debug("Done culling");
}

function Cull(vehicle) {
	local name = AIVehicle.GetName(vehicle);
	if (name != null && name.find("X") == null) {
		AIVehicle.SetName(vehicle, "X" + name);
	}

	if (!AIOrder.IsGotoDepotOrder(vehicle, AIOrder.ORDER_CURRENT)) {
		AIVehicle.SendVehicleToDepot(vehicle);
	}
}

function IsOnlyTrainServicingStation(train) {
	local stations = AIStationList_Vehicle(train);
	for (local station = stations.Begin(); stations.HasNext(); station = stations.Next()) {
		local vehicles = AIVehicleList_Station(station);
		if (vehicles.Count() <= 1) {
			Debug("Train" + AIVehicle.GetName(train) + " is the only one servicing station " + AIStation.GetName(station));
			return true;
		}
	}
	
	return false;
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


class ReplaceBus extends Task {
	vehicle = null;

	constructor(parentTask, vehicle) {
		// FIXME also gets called for road vehicles
		Task.constructor(parentTask);
		this.vehicle = vehicle;
	}

	function _tostring() {
		return "ReplaceBus " + AIVehicle.GetName(vehicle);
	}

	function Run() {
		if (!AIVehicle.IsValidVehicle(vehicle)) {
			throw TaskFailedException("Bus no longer exists");
		}

		local depot = GetDepot(vehicle);
		local engineType = BuildBus.GetEngine(PAX)
		local newVehicle = AIVehicle.BuildVehicle(depot, engineType);
		CheckError();

		GenerateName(newVehicle, depot, "W");
		AIOrder.ShareOrders(newVehicle, vehicle);
		AIVehicle.StartStopVehicle(newVehicle);
		Cull(vehicle);
	}
}
