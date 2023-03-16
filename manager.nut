/**
 * Clone the top 10%, and cull the bottom 10%.
 */
function CullTrains() {
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
	trains.Valuate(AIVehicle.GetProfitLastYear);
	
	local n = trains.Count();
	local best = AIList();
	local worst = AIList();
	best.AddList(trains);
	worst.AddList(trains);
	
	best.KeepTop(n/10);
	worst.KeepBottom(n/10);
	
	local clones = 0;
	foreach (train, profit in best) {
		Debug("Cloning " + AIVehicle.GetName(train) + ", made " + profit + " last year");
		local copy = Clone(train);
		if (AIVehicle.IsValidVehicle(copy)) {
			AIVehicle.StartStopVehicle(copy);
			clones++;
		}
	}
	
	foreach (train, profit in worst) {
		Debug("Culling " + AIVehicle.GetName(train) + ", made " + profit + " last year");
		Cull(train);
		clones--;
		if (clones <= 0)
			break;
	}
	
	Debug("Done culling");
}

function Cull(vehicle) {
	local name = AIVehicle.GetName(vehicle);
	if (name != null && name.find("X") == null) {
		AIVehicle.SendVehicleToDepot(vehicle);
		AIVehicle.SetName(vehicle, "X" + name);
	}
}
