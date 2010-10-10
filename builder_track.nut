class BuildTrack extends Task {

	// build styles
	static STRAIGHT = 0;
	static LOOSE = 1;
	static FAST = 2;
	static FOLLOW = 3;
	
	static SIGNAL_INTERVAL = 3;
	//static DEPOT_INTERVAL = 30;
	static DEPOT_INTERVAL = 0;
	
	a = null;
	b = null;
	c = null;
	d = null;
	ignored = null;
	signalMode = null;
	network = null;
	style = null;
	path = null;
	lastDepot = null;
	
	constructor(parentTask, from, to, ignored, signalMode, network, style = null) {
		Task.constructor(parentTask); 
		this.a = from[0];
		this.b = from[1];
		this.c = to[0];
		this.d = to[1];
		this.ignored = ignored;
		this.signalMode = signalMode;
		this.network = network;
		this.style = style ? style : STRAIGHT;
		
		//this.lastDepot = -DEPOT_INTERVAL;	// build one as soon as possible
		this.lastDepot = 0;
		this.path = null;
	}
	
	function _tostring() {
		return "BuildTrack";
	}
	
	function Run() {
		SetConstructionSign(a, this);
		
		/*
		AISign.BuildSign(a, "a");
		AISign.BuildSign(b, "b");
		AISign.BuildSign(c, "c");
		AISign.BuildSign(d, "d");
		*/
		
		if (!path) path = FindPath();
		ClearSecondarySign();
		if (!path) throw TaskFailedException("no path");
		BuildPath(path);
	}
	
	function GetPath() {
		return path;
	}
	
	function FindPath() {
		local pathfinder = Rail();
		
		local bridgeLength = GetMaxBridgeLength();
		pathfinder.cost.max_bridge_length = bridgeLength;
		pathfinder.cost.max_tunnel_length = 5;
		switch (AIController.GetSetting("PathfinderMultiplier")) {
			case 1:  pathfinder.estimate_multiplier = 1.1; break;
			case 2:  pathfinder.estimate_multiplier = 1.4; break;
			case 3:  pathfinder.estimate_multiplier = 1.7; break;
			default: pathfinder.estimate_multiplier = 2.0; break;
		}
		
		local u = pathfinder.cost.tile;
		pathfinder.cost.max_cost = u * 4 * AIMap.DistanceManhattan(a, d);
		
		if (style == STRAIGHT) {
			// straight, avoiding obstacles
			pathfinder.cost.diagonal_tile = u;
			pathfinder.cost.turn = 2*u;
			pathfinder.cost.adj_obstacle = 4*u;
		} else if (style == FOLLOW) {
			// cheaper turns, bonus for nearby track
			pathfinder.cost.diagonal_tile = u;
			pathfinder.cost.turn = u/2;
			pathfinder.cost.slope = u/2;
			pathfinder.cost.adj_obstacle = 0;
			pathfinder.cost.adj_rail = -u;
		} else if (style == LOOSE) {
			pathfinder.cost.diagonal_tile = 40;
			pathfinder.cost.turn = 25;
			pathfinder.cost.slope = 300;
		} else {
			pathfinder.cost.diagonal_tile = 70;
		}
		
		// high multiplier settings make it very bridge happy, so increase the cost
		pathfinder.cost.bridge_per_tile = 200 + (200 * pathfinder.estimate_multiplier);
		pathfinder.cost.tunnel_per_tile = 100;
		
		// Pathfinding needs money since it attempts to build in test mode.
		// We can't get the price of a tunnel, but we can get it for a bridge
		// and we'll assume they're comparable.
		local maxBridgeCost = GetMaxBridgeCost(pathfinder.cost.max_bridge_length);
		if (GetBankBalance() < maxBridgeCost*2) {
			throw NeedMoneyException(maxBridgeCost*2);
		}
		
		SetSecondarySign("Pathfinding...");
		pathfinder.InitializePath([[b, a]], [[c, d]], ignored);
		return pathfinder.FindPath(AIMap.DistanceManhattan(a, d) * 3 * TICKS_PER_DAY);
	}
	
	function BuildPath(path) {
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local count = 1;	// don't start with signals right away
		while (node != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, node.GetTile()) > 1) {
					local length = AIMap.DistanceManhattan(node.GetTile(), prev) + 1;
					if (AITunnel.GetOtherTunnelEnd(prev) == node.GetTile()) {
						// since we can resume building, check if there already is a tunnel
						if (!AITunnel.IsTunnelTile(prev)) {
							AITunnel.BuildTunnel(AIVehicle.VT_RAIL, prev);
							costEstimate = GetMaxBridgeCost(length);
							CheckError();
						}
					} else {
						local bridge_list = AIBridgeList_Length(length);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);
						AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, node.GetTile());
						//costEstimate = GetMaxBridgeCost(length);
						CheckError();
					}
					prevprev = prev;
					prev = node.GetTile();
					node = node.GetParent();
				} else {
					local built = AIRail.BuildRail(prevprev, prev, node.GetTile());
					
					// reset our cost estimate, because we can continue building track even with
					// only a little money
					//costEstimate = 5000;
					CheckError();
					
					// since we can be restarted, we can process a tile more than once
					// don't build signals again, or they'll be flipped around!
					local forward = signalMode == SignalMode.FORWARD;
					local front = forward ? node.GetTile() : prevprev;
					if (signalMode != SignalMode.NONE &&
					    count % SIGNAL_INTERVAL == 0 &&
					    AIRail.GetSignalType(prev, front) == AIRail.SIGNALTYPE_NONE)
					{
						AIRail.BuildSignal(prev, front, AIRail.SIGNALTYPE_NORMAL);
					}
					
					local possibleDepot = DEPOT_INTERVAL > 0 && prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), forward, true) : null;
					if (count % SIGNAL_INTERVAL == 1 && count - lastDepot > DEPOT_INTERVAL && depotSite) {
						if (AIRail.BuildRailDepot(depotSite, prev) &&
							AIRail.BuildRail(depotSite, prev, prevprev) &&
							AIRail.BuildRail(depotSite, prev, node.GetTile())) {
							// success
							lastDepot = count;
							network.depots.append(depotSite);
						} else {
							AITile.DemolishTile(depotSite);
							AIRail.RemoveRail(depotSite, prev, prevprev);
							AIRail.RemoveRail(depotSite, prev, node.GetTile());
						}							
					}
					
					count++;
				}
			}
			
			if (node != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = node.GetTile();
				node = node.GetParent();
			}
		}
	}
	
	/**
	 * Return a tile suitable for building a depot, or null.
	 */
	function GetDepotSite(prevprev, prev, tile, next, nextnext, forward, checkBuildable) {
		// depots are built off to the right side of the track
		// site is suitable if the tiles are in a straight X or Y line
		local coordinates = [
			TileCoordinates(prevprev),
			TileCoordinates(prev),
			TileCoordinates(tile),
			TileCoordinates(next),
			TileCoordinates(nextnext)
		];
		
		local depotSite = null;
		if (MatchCoordinates(coordinates, 0)) {
			// same X
			if (coordinates[0][1] < coordinates[1][1]) {
				// increasing Y
				depotSite = AIMap.GetTileIndex(coordinates[2][0] + (forward ? -1 : 1), coordinates[2][1]);
			} else {
				// decreasing Y
				depotSite = AIMap.GetTileIndex(coordinates[2][0] + (forward ? 1 : -1), coordinates[2][1]);
			}
			
		} else if (MatchCoordinates(coordinates, 1)) {
			// same Y
			if (coordinates[0][0] < coordinates[1][0]) {
				// increasing X
				depotSite = AIMap.GetTileIndex(coordinates[2][0], coordinates[2][1] + (forward ? 1 : -1));
			} else {
				// decreasing X
				depotSite = AIMap.GetTileIndex(coordinates[2][0], coordinates[2][1] + (forward ? -1 : 1));
			}
		}
		
		return (depotSite && (!checkBuildable || AITile.IsBuildable(depotSite))) ? depotSite : null; 
	}
	
	/**
	 * Test whether the X or Y coordinates of a list are all the same.
	 */
	function MatchCoordinates(coordinates, index) {
		local value = coordinates[0][index];
		foreach (c in coordinates) {
			if (c[index] != value) return false;
		}
		
		return true;
	}
	
	function TileCoordinates(tile) {
		return [AIMap.GetTileX(tile), AIMap.GetTileY(tile)];
	}
	
	function Failed() {
		Task.Failed();
		
		if (path == false) {
			// no path found
			return;
		}
		
		Debug("Removing...");
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		while (node != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, node.GetTile()) > 1) {
					// bridge or tunnel
					AITile.DemolishTile(prev);
					prevprev = prev;
					prev = node.GetTile();
					node = node.GetParent();
				} else {
					AIRail.RemoveRail(prevprev, prev, node.GetTile());
					local possibleDepot = prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), signalMode == SignalMode.FORWARD, false) : null;
					if (depotSite && AIRail.IsRailDepotTile(depotSite)) {
						AITile.DemolishTile(depotSite);
						AIRail.RemoveRail(depotSite, prev, prevprev);
						AIRail.RemoveRail(depotSite, prev, node.GetTile());
					}
				}
			}
			
			if (node != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = node.GetTile();
				node = node.GetParent();
			}
		}
		
		Debug("Done!");
	}
}

class BuildSignals extends Builder {
	
	trackBuilder = null;
	signalMode = null;
	
	constructor(trackBuilder, signalMode) {
		this.trackBuilder = trackBuilder;
		this.signalMode = signalMode;
	}
	
	function Run() {
		local path = trackBuilder.GetPath();
		Debug("Building signals...");
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local count = 1;	// don't start with signals right away
		while (node != null) {
			if (prevprev != null) {
				if (AIMap.DistanceManhattan(prev, node.GetTile()) > 1) {
					// tunnel or bridge - no signals
					prevprev = prev;
					prev = node.GetTile();
					node = node.GetParent();
				} else {
					// since we can be restarted, we can process a tile more than once
					// don't build signals again, or they'll be flipped around!
					local forward = signalMode == SignalMode.FORWARD;
					local front = forward ? node.GetTile() : prevprev;
					if (signalMode != SignalMode.NONE &&
					    count % BuildTrack.SIGNAL_INTERVAL == 0 &&
					    AIRail.GetSignalType(prev, front) == AIRail.SIGNALTYPE_NONE)
					{
						AIRail.BuildSignal(prev, front, AIRail.SIGNALTYPE_NORMAL);
					}
					
					count++;
				}
			}
			
			if (node != null) {
				prevprevprev = prevprev;
				prevprev = prev;
				prev = node.GetTile();
				node = node.GetParent();
			}
		}
		
		Debug("Done!");
	}
}
