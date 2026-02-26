function GenerateName(vehicle, depot, prefix="T") {
	local i = 0;
	while (!AIVehicle.SetName(vehicle, prefix + i + "D" + depot)) {
		i++;
	}
}

function IsBranchLineTrain(train) {
	local name = AIVehicle.GetName(train);
	return name[0] == "B";
}

function IsBranchLineStation(station) {
	local name = AIStation.GetName(station);
	return EndsWith(name, " B");
}

function GetDepot(train) {
	// D<tile index>
	local name = AIVehicle.GetName(train);
	local depot = name.slice(name.find("D") + 1).tointeger();
	return depot;
}

function Clone(train) {
	local depot = GetDepot(train);
	local copy = AIVehicle.CloneVehicle(depot, train, true);
	if (AIVehicle.IsValidVehicle(copy)) {
		GenerateName(copy, depot);	
	}
	
	return copy;
}
