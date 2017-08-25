function GenerateName(train, depot) {
	local i = 0;
	while (!AIVehicle.SetName(train, "T" + i + "D" + depot)) {
		i++;
	}
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
