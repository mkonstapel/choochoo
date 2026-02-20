import("pathfinder.road", "Road", 3);

class BuildRoad extends Task {

	stationTile = null;
	town = null;
	path = null;

	constructor(parentTask, stationTile, town) {
		Task.constructor(parentTask);
		this.stationTile = stationTile;
		this.town = town;
		this.path = null;
	}

	function _tostring() {
		return "BuildRoad";
	}

	function Run() {
		SetConstructionSign(stationTile, this);

		local depot = TrainStation.AtLocation(stationTile).GetRoadDepotExit();
		local center = AITown.GetLocation(town);
		if (!path) path = FindPath(depot, center);
		ClearSecondarySign();
		if (!path) throw TaskFailedException("no path");
		BuildPath(path);
	}

	function GetPath() {
		return path;
	}

	function FindPath(a, b) {
		local pathfinder = Road();
		pathfinder.cost.max_bridge_length = 4;
		pathfinder.cost.max_tunnel_length = 4;
		pathfinder.cost.no_existing_road = pathfinder.cost.tile; // we want reuse
		pathfinder.cost.max_cost = pathfinder.cost.tile * 4 * max(10, AIMap.DistanceManhattan(a, b));

		// Pathfinding needs money since it attempts to build in test mode.
		// We can't get the price of a tunnel, but we can get it for a bridge
		// and we'll assume they're comparable.
		local maxBridgeCost = GetMaxBridgeCost(pathfinder.cost.max_bridge_length);
		if (GetBankBalance() < maxBridgeCost*2) {
			throw NeedMoneyException(maxBridgeCost*2);
		}

		SetSecondarySign("Pathfinding...");
		pathfinder.InitializePath([a], [b]);
		return pathfinder.FindPath(AIMap.DistanceManhattan(a, b) * 3 * TICKS_PER_DAY);
	}

	function BuildPath(path) {
		while (path != null) {
			local par = path.GetParent();
			if (par != null) {
				local last_node = path.GetTile();
				if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
					// building from path to par fails if trying to build from a bridge to a clear tile in 14.0RC1
					// try building it in the other direction? That works in the UI
					if (AIRoad.AreRoadTilesConnected(path.GetTile(), par.GetTile())) {
						// already connected
					} else if (!AIRoad.BuildRoad(path.GetTile(), par.GetTile())) {
						// VEHICLE_IN_THE_WAY is expected, I just want to see if the error in RC1 mentioned above still happens
						if (AIError.GetLastError() != AIError.ERR_VEHICLE_IN_THE_WAY) {
							Error("Couldn't build road at " + TileToString(path.GetTile()) + " to " + TileToString(par.GetTile()) + ": " + AIError.GetLastErrorString());
							if (AIRoad.BuildRoad(par.GetTile(), path.GetTile())) {
								Warning("But the other way around worked");
							} else {
								CheckError();
							}
						} else {
							CheckError();
						}
					}
				} else {
					/* Build a bridge or tunnel. */
					if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
						/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
						if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
						if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
							if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
								CheckError();
							}
						} else {
							local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
							bridge_list.Valuate(AIBridge.GetMaxSpeed);
							bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);
							if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
								CheckError();
							}
						}
					}
				}
			}
			path = par;
		}
	}

	function Failed() {
		Task.Failed();
		// TODO: remove road
	}

}