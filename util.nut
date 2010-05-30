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

function TrainLength(train) {
	// train length in tiles
	return (AIVehicle.GetLength(train) + 15) / 16;
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
