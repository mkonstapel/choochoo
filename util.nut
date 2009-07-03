function Debug(s) {
	AILog.Info(GetDate() + ": " + s);
}

function Warning(s) {
	AILog.Warning(GetDate() + ": " + s);
}

function Error(s) {
	AILog.Error(GetDate() + ": " + s);
}

function GetDate() {
	local date = AIDate.GetCurrentDate();
	return "" + AIDate.GetYear(date) + "-" + AIDate.GetMonth(date) + "-" + AIDate.GetDayOfMonth(date);
}

function PrintError() {
	Error(AIError.GetLastErrorString());
}

function Sign(x) {
	if (x < 0) return -1;
	if (x > 0) return 1;
	return 0;
}

/**
 * Create a string of all elements of an array, separated by a comma.
 */
function ArrayToString(a) {
	local s = "";
	foreach (index, item in a) {
		if (index > 0) s += ", ";
		s += item;
	}
	
	return s;
}

/**
 * Add a rectangular area to an AITileList containing tiles that are within /radius/
 * tiles from the center tile, taking the edges of the map into account.
 */  
function SafeAddRectangle(list, tile, radius) {
	local x1 = max(0, AIMap.GetTileX(tile) - radius);
	local y1 = max(0, AIMap.GetTileY(tile) - radius);
	
	local x2 = min(AIMap.GetMapSizeX() - 2, AIMap.GetTileX(tile) + radius);
	local y2 = min(AIMap.GetMapSizeY() - 2, AIMap.GetTileY(tile) + radius);
	
	list.AddRectangle(AIMap.GetTileIndex(x1, y1),AIMap.GetTileIndex(x2, y2)); 
}

/**
 * Find the cargo ID for passengers.
 * Otto: newgrf can have tourist (TOUR) which qualify as passengers but townfolk won't enter the touristbus...
 * hence this rewrite; you can check for PASS as string, but this is discouraged on the wiki
 */
function GetPassengerCargoID() {
	local list = AICargoList();
	local candidate = -1;
	for (local i = list.Begin(); list.HasNext(); i = list.Next()) {
		if (AICargo.HasCargoClass(i, AICargo.CC_PASSENGERS))
		candidate = i;
	}
	if(candidate != -1)
		return candidate;
	
	throw "no passenger cargo in this game!";
}