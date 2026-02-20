function GenerateName(train, depot, prefix="T") {
	local i = 0;
	while (!AIVehicle.SetName(train, prefix + i + "D" + depot)) {
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

function Replace(train) {
	// build a replacement for a train using a newer engine and wagons
	// TODO this should be a task so it can be retried if we run out of money
	// TODO for branch trains, this should first send the original train to the depot to prevent deadlocking the branch line
	local depot = GetDepot(train);
	local engineType = AIVehicle.GetEngineType(train);
	local railType = AIEngine.GetRailType(engine);
	// select and build engine
	// add equal number of wagons
	// remove wagons while longer than original train
	// cull original train
	return copy;
}
