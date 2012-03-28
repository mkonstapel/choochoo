function Debug(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Info(GetDate() + ":" + s);
}

function Warning(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Warning(GetDate() + ":" + s);
}

function Error(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Error(GetDate() + ":" + s);
}

function GetDate() {
	local date = AIDate.GetCurrentDate();
	return "" + AIDate.GetYear(date) + "-" + ZeroPad(AIDate.GetMonth(date)) + "-" + ZeroPad(AIDate.GetDayOfMonth(date));
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
 * Calculates an integer square root.
 */
function Sqrt(i) {
	if (i == 0)
		return 0;   // Avoid divide by zero
	local n = (i / 2) + 1;       // Initial estimate, never low
	local n1 = (n + (i / n)) / 2;
	while (n1 < n) {
		n = n1;
		n1 = (n + (i / n)) / 2;
	}
	return n;
}

function Min(a, b) {
	return a < b ? a : b;
}

function Range(from, to) {
	local range = [];
	for (local i=from; i<to; i++) {
		range.append(i);
	}
	
	return range;
}

/**
 * Return the closest integer equal to or greater than x.
 */
function Ceiling(x) {
	if (x.tointeger().tofloat() == x) return x.tointeger();
	return x.tointeger() + 1;
}

function RandomTile() {
	return abs(AIBase.Rand()) % AIMap.GetMapSize();
}

/**
 * Sum up the values of an AIList.
 */
function Sum(list) {
	local sum = 0;
	for (local item = list.Begin(); list.HasNext(); item = list.Next()) {
		sum += list.GetValue(item);
	}
	
	return sum;
}

/**
 * Create a string of all elements of an array, separated by a comma.
 */
function ArrayToString(a) {
	if (a == null) return "";
	
	local s = "";
	foreach (index, item in a) {
		if (index > 0) s += ", ";
		s += item;
	}
	
	return s;
}

/**
 * Turn a tile index into an "x, y" string.
 */
function TileToString(tile) {
	return "(" + AIMap.GetTileX(tile) + ", " + AIMap.GetTileY(tile) + ")";
}

/**
 * Concatenate the same string, n times.
 */
function StringN(s, n) {
	local r = "";
	for (local i=0; i<n; i++) {
		r += s;
	}
	
	return r;
}

function ZeroPad(i) {
	return i < 10 ? "0" + i : "" + i;
}

function StartsWith(a, b) {
	return a.find(b) == 0;
}

/**
 * Swap two tiles - used for swapping entrance/exit tile strips.
 */
function Swap(tiles) {
	return [tiles[1], tiles[0]];
}

/**
 * Create an array from an AIList.
 */
function ListToArray(l) {
	local a = [];
	for (local item = l.Begin(); l.HasNext(); item = l.Next()) a.append(item);
	return a;
}

/**
 * Create an AIList from an array.
 */
function ArrayToList(a) {
	local l = AIList();
	foreach (item in a) l.AddItem(item, 0);
	return l;
}

/**
 * Return an array that contains all elements of a and b.
 */
function Concat(a, b) {
	local r = [];
	r.extend(a);
	r.extend(b);
	return r;
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
 * Filter an AITileList for AITile.IsBuildable tiles.
 */
function KeepBuildableArea(area) {
	area.Valuate(AITile.IsBuildable);
	area.KeepValue(1);
	return area;
}

function InverseDirection(direction) {
	switch (direction) {
		case Direction.N: return Direction.S;
		case Direction.E: return Direction.W;
		case Direction.S: return Direction.N;
		case Direction.W: return Direction.E;
		
		case Direction.NE: return Direction.SW;
		case Direction.SE: return Direction.NW;
		case Direction.SW: return Direction.NE;
		case Direction.NW: return Direction.SE;
		default: throw "invalid direction";
	}
}

function DirectionName(direction) {
	switch (direction) {
		case Direction.N: return "N";
		case Direction.E: return "E";
		case Direction.S: return "S";
		case Direction.W: return "W";
		
		case Direction.NE: return "NE";
		case Direction.SE: return "SE";
		case Direction.SW: return "SW";
		case Direction.NW: return "NW";
		default: throw "invalid direction";
	}
}

/**
 * Find the cargo ID for passengers.
 * Otto: newgrf can have tourist (TOUR) which qualify as passengers but townfolk won't enter the touristbus...
 * hence this rewrite; you can check for PASS as string, but this is discouraged on the wiki
 */
function GetPassengerCargoID() {
	return GetCargoID(AICargo.CC_PASSENGERS);
}

function GetMailCargoID() {
	return GetCargoID(AICargo.CC_MAIL);
}

function GetCargoID(cargoClass) {
	local list = AICargoList();
	local candidate = -1;
	for (local i = list.Begin(); list.HasNext(); i = list.Next()) {
		if (AICargo.HasCargoClass(i, cargoClass))
		candidate = i;
	}
	
	if(candidate != -1)
		return candidate;
	
	throw "missing required cargo class";
}

function GetMaxBridgeLength() {
	local length = AIController.GetSetting("MaxBridgeLength");
	while (length > 0 && AIBridgeList_Length(length).IsEmpty()) {
		length--;
	}
	
	return length;
}

function GetMaxBridgeCost(length) {
	local bridges = AIBridgeList_Length(length);
	if (bridges.IsEmpty()) throw "Cannot build " + length + " tile bridges!";
	bridges.Valuate(AIBridge.GetMaxSpeed);
	bridges.KeepTop(1);
	local bridge = bridges.Begin();
	return AIBridge.GetPrice(bridge, length);
}

function TrainLength(train) {
	// train length in tiles
	return (AIVehicle.GetLength(train) + 15) / 16;
}

function HaveHQ() {
	return AICompany.GetCompanyHQ(COMPANY) != AIMap.TILE_INVALID;
}

function GetEngine(cargo, railType, bannedEngines, cheap) {
	local engineList = AIEngineList(AIVehicle.VT_RAIL);
	engineList.Valuate(AIEngine.IsWagon);
	engineList.KeepValue(0);
	engineList.Valuate(AIEngine.CanRunOnRail, railType);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.HasPowerOnRail, railType);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.CanPullCargo, cargo);
	engineList.KeepValue(1);
	engineList.RemoveList(ArrayToList(bannedEngines));
	
	engineList.Valuate(AIEngine.GetPrice);
	if (cheap) {
		// go for the cheapest
		engineList.KeepBottom(1);
	} else {
		// pick something middle of the range, by removing the top half
		// this will hopefully give us something decent, even when faced with newgrf train sets
		engineList.Sort(AIList.SORT_BY_VALUE, true);
		engineList.RemoveTop(engineList.Count() / 2);
	}
	
	if (engineList.IsEmpty()) throw TaskFailedException("no suitable engine");
	return engineList.Begin();
}

function GetWagon(cargo, railType) {
	// select the largest appropriate wagon type
	local engineList = AIEngineList(AIVehicle.VT_RAIL);
	engineList.Valuate(AIEngine.CanRefitCargo, cargo);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.IsWagon);
	engineList.KeepValue(1);
	
	engineList.Valuate(AIEngine.CanRunOnRail, railType);
	engineList.KeepValue(1);
	
	// prefer engines that can carry this cargo without a refit,
	// because their refitted capacity may be different from
	// their "native" capacity - for example, NARS Ore Hoppers
	local native = AIList();
	native.AddList(engineList);
	native.Valuate(AIEngine.GetCargoType);
	native.KeepValue(cargo);
	if (!native.IsEmpty()) {
		engineList = native;
	}
	
	engineList.Valuate(AIEngine.GetCapacity)
	engineList.KeepTop(1);
	
	if (engineList.IsEmpty()) throw TaskFailedException("no suitable wagon");
	return engineList.Begin();
}

function MaxDistance(cargo, trainLength) {
	// maximum safe rail distance we can expect to build with our starting loan
	local rail = AIRail.GetCurrentRailType();
	local engine = GetEngine(cargo, rail, [], true);
	local wagon = GetWagon(cargo, rail);
	local trainCost = AIEngine.GetPrice(engine) + AIEngine.GetPrice(wagon) * (trainLength-1) * 2;
	local bridgeCost = GetMaxBridgeCost(GetMaxBridgeLength());
	local tileCost = AIRail.GetBuildCost(rail, AIRail.BT_TRACK);
	return (AICompany.GetMaxLoanAmount() - trainCost - bridgeCost) / tileCost;
}

function GetGameSetting(setting, defaultValue) {
	return AIGameSettings.IsValid(setting) ? AIGameSettings.GetValue(setting) : defaultValue;
}

class Counter {
	
	count = 0;
	
	constructor() {
		count = 0;
	}
	
	function Get() {
		return count;
	}
	
	function Inc() {
		count++;
	}
}

/**
 * A boolean flag, usable as a static field.
 */
class Flag {
	
	value = null;
	
	constructor() {
		value = false;
	}
	
	function Set(value) {
		this.value = value;
	}
	
	function Get() {
		return value;
	}
}
