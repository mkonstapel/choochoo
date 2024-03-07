class BuildTrack extends Task {

	// build styles
	static STRAIGHT = 0;
	static LOOSE = 1;
	static FAST = 2;
	static FOLLOW = 3;
	
	//static DEPOT_INTERVAL = 30;
	static DEPOT_INTERVAL = 0;
	
	a = null;
	b = null;
	c = null;
	d = null;
	ignored = null;
	signalMode = null;
	signalInterval = null;
	network = null;
	style = null;
	path = null;
	lastDepot = null;
	follow = null;
	
	constructor(parentTask, from, to, ignored, signalMode, network, style = null, follow = null) {
		Task.constructor(parentTask); 
		this.a = from[0];
		this.b = from[1];
		this.c = to[0];
		this.d = to[1];
		this.ignored = ignored;
		this.signalMode = signalMode;
		this.signalInterval = network.trainLength + 1;
		this.network = network;
		this.style = style ? style : STRAIGHT;
		this.follow = follow;
		
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
		
		local startDate = AIDate.GetCurrentDate();
		if (!path) path = FindPath();
		local endDate = AIDate.GetCurrentDate();
		local days = endDate - startDate;

		ClearSecondarySign();
		if (path == null) throw TaskFailedException("no path after " + days + " days");
		if (path == false) throw TaskFailedException("gave up after " + days + " days");
		Debug("    Found path in " + days + " days");
		BuildPath(path);
	}
	
	function GetPath() {
		return path;
	}
	
	function FindPath() {
		local startDate = AIDate.GetCurrentDate()
		local pathfinder = Rail();
		local bridgeLength = GetMaxBridgeLength();
		pathfinder.cost.max_bridge_length = bridgeLength;
		pathfinder.cost.max_tunnel_length = 8;
		if (follow) pathfinder.follow = PathToList(follow.GetPath());
		
		switch (AIController.GetSetting("PathfinderMultiplier")) {
			case 1:  pathfinder.estimate_multiplier = 1.1; break;
			case 2:  pathfinder.estimate_multiplier = 1.4; break;
			case 3:  pathfinder.estimate_multiplier = 1.7; break;
			default: pathfinder.estimate_multiplier = 2.0; break;
		}
		
		local u = pathfinder.cost.tile;
		//pathfinder.cost.max_cost = u * 4 * AIMap.DistanceManhattan(a, d);
		pathfinder.cost.slope = 0.1*u;
		pathfinder.cost.coast = 0.1*u;

		// High multiplier settings make it very bridge happy, because bridges
		// and tunnels jump towards the goal, making all intermediate tiles
		// seem bad options because they are being overestimated. We have to
		// increase the cost to make it prefer short bridges.
		pathfinder.cost.bridge_per_tile = 2*u + (5*u * pathfinder.estimate_multiplier);
		// The terrain is rarely suitable for tunnels, so when it is, might as
		// well use it. Tunnels are limited in length, and they aren't
		// eyesores like big cantilever bridges.
		pathfinder.cost.tunnel_per_tile = 0.5*u;
		
		if (style == STRAIGHT) {
			// straight, avoiding obstacles
			
			// Do we care about turns? If not, pathfinding may be a little faster
			// since we don't need to calculate turn costs. The windy snaky paths
			// may be a feature, but for rail lines I like the straighter paths,
			// so some cost for turns it is.
			pathfinder.cost.turn = 2*u;
			// pathfinder.cost.turn = 0;

			// we don't really care about slopes, and that speeds up pathfinding
			pathfinder.cost.slope = 0;
			pathfinder.cost.diagonal_tile = u;
			pathfinder.cost.adj_obstacle = 5*u;
		} else if (style == FOLLOW) {
			// cheaper turns, penalty for no nearby track
			pathfinder.cost.no_adj_rail = 2*u;
			pathfinder.cost.diagonal_tile = (0.8*u);
			pathfinder.cost.turn = 0.1*u;
			// pathfinder.cost.turn = 0;
			pathfinder.cost.slope = 0;
			pathfinder.cost.adj_obstacle = 0;
		} else if (style == LOOSE) {
			pathfinder.cost.diagonal_tile = (0.4*u);
			pathfinder.cost.turn = 0.25*u;
			pathfinder.cost.slope = 3*u;
		} else {
			pathfinder.cost.diagonal_tile = (0.7*u);

			// fastest pathfinding disregards both turns and slopes
			pathfinder.cost.turn = 0;
			pathfinder.cost.slope = 0;
		}
		
		// Pathfinding needs money since it attempts to build in test mode.
		// We can't get the price of a tunnel, but we can get it for a bridge
		// and we'll assume they're comparable.
		local maxBridgeCost = GetMaxBridgeCost(pathfinder.cost.max_bridge_length);
		if (GetBankBalance() < maxBridgeCost*2) {
			throw NeedMoneyException(maxBridgeCost*2);
		}
		
		SetSecondarySign("Pathfinding...");
		pathfinder.InitializePath([[b, a]], [[c, d]], ignored);

		// how long should we search?
		// do we want to search longer on longer routes?
		// do we want to search "harder" if we really need this track?
		local startDate = AIDate.GetCurrentDate();
		local endDate = startDate + 365; 
		local res = null;
		local distance = Sqrt(AIMap.DistanceSquare(a, d));

		// track our best and worst considered options, in terms of remaining distance
		// to show how far the pathfinder is in terms of homing in on the destination
		local upperBound = 0;
		local lowerBound = 0;
		local alpha = 0.05;
		while (true) {
			res = pathfinder.FindPath(1000);
			if (res == false) {
				// see if we want to continue
				local date = AIDate.GetCurrentDate();
				if (date > endDate) {
					break;
				}

				// not sure if I like the "progress bar"

				/*
				local best = pathfinder._pathfinder._open.Peek();
				local tile = best.GetTile();
				local remaining = Sqrt(AIMap.DistanceSquare(tile, d));

				if (remaining > upperBound) {
					upperBound = remaining;
				} else {
					upperBound = alpha * remaining + (1-alpha) * upperBound;
				}

				if (remaining < lowerBound) {
					lowerBound = remaining;
				} else {
					lowerBound = alpha * remaining + (1-alpha) * lowerBound;
				}

				local current = 100 * (distance - remaining) / distance;
				local worst = 100 * (distance - upperBound) / distance;
				local best = 100 * (distance - lowerBound) / distance;
				local bar = "";
				local didCurrent = false;
				local didWorst = false;
				local didBest = false;
				for (local i = -100; i < 110; i += 10) {
					if (i == 0) {
						bar += " ";
					} else if (!didWorst && i >= worst) {
						bar += "[";
						didWorst = true;
					} else if (!didCurrent && i >= current) {
						bar += i < 0 ? "<" : ">";
						didCurrent = true;
					} else if (!didBest && i >= best) {
						bar += "]";
						didBest = true;
					} else {
						bar += "-";
					}
				}
				SetSecondarySign(bar);
				*/
			} else {
				// we either found a path, or concluded there isn't one
				break;
			}
		}

		// pathfinder performance report
		/*
		try {
			local outcome;
			if (res == null) {
				outcome = "no path exists";
			} else if (res == false) {
				outcome = "timed out";
			} else {
				outcome = "path of " + PathToList(res).Count() + " tiles";
			}
			local opsPerDay = 10000 * TICKS_PER_DAY;
			Debug("Pathfinder took", AIDate.GetCurrentDate() - startDate, "days:", outcome);
			Debug("Callback costs:");
			Debug("- Cost:", pathfinder.costOps / opsPerDay, "days", pathfinder.costCalls, "calls ", pathfinder.costOps, "ops,",  pathfinder.costOps / pathfinder.costCalls, "ops per call");
			Debug("- Neighbours:", pathfinder.neighbourOps / opsPerDay, "days", pathfinder.neighbourCalls, "calls", pathfinder.neighbourOps, "ops,",  pathfinder.neighbourOps / pathfinder.neighbourCalls, "ops per call");
			Debug("- Estimate:", pathfinder.estimateOps / opsPerDay, "days", pathfinder.estimateCalls, "calls", pathfinder.estimateOps, "ops",  pathfinder.estimateOps / pathfinder.estimateCalls, "ops per call");
			Debug("- A* pop:", pathfinder._pathfinder.popOps);
			Debug("- A* goal:", pathfinder._pathfinder.goalOps);
			Debug("- A* neighbour:", pathfinder._pathfinder.neighbourOps);
		} catch (e) {
			Error("Error creating pathfinder report", e);
		}
		*/

		return res;
	}
	
	function PathToList(path) {
		local list = AIList();
		local node = path;
		while (node != null) {
			list.AddItem(node.GetTile(), 1);
			node = node.GetParent();
		}
		
		return list;
	}

	function SelectBridge(length) {
		local bridge_list = AIBridgeList_Length(length);
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, false);

		// Prefer not to use cantilever bridges because I think they're ugly
		// and (even more IMHO) I think the subtle coppery suspension bridges
		// look better than the faster yellow ones. Of course, this does not
		// take NewGRFs into account, just the base game but that's OK, it'll
		// still pick a "working" bridge.
		local bridge = bridge_list.Begin();
		if (AIController.GetSetting("PrettyBridges") != 0) {
			while (bridge_list.HasNext()) {
				local name = AIBridge.GetName(bridge).tolower();
				local isCantilever = name.find("cantilever") != null;
				local isSuspension = name.find("suspension") != null;
				local isYellowSuspension = isSuspension && AIBridge.GetMaxSpeed(bridge) == 112;
				if (!isCantilever && !isYellowSuspension) {
					break;
				}

				bridge = bridge_list.Next();
			}
		}

		return bridge;
	}
	
	function BuildPath(path) {
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;

		// trains take up more space on diagonals and we want to make sure
		// they clear the exit of stations and junctions, so the first signal
		// block should be two tiles longer
		local count = -2;
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
						AIBridge.BuildBridge(AIVehicle.VT_RAIL, SelectBridge(length), prev, node.GetTile());
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
						count > 0 &&
					    count % signalInterval == 0 &&
					    AIRail.GetSignalType(prev, front) == AIRail.SIGNALTYPE_NONE)
					{
						AIRail.BuildSignal(prev, front, AIRail.SIGNALTYPE_NORMAL);
					}
					
					local possibleDepot = DEPOT_INTERVAL > 0 && prevprevprev && node.GetParent();
					local depotSite = possibleDepot ? GetDepotSite(prevprevprev, prevprev, prev, node.GetTile(), node.GetParent().GetTile(), forward, true) : null;
					if (count % signalInterval == 1 && count - lastDepot > DEPOT_INTERVAL && depotSite) {
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
	
	constructor(trackBuilder, signalMode, signalInterval) {
		this.trackBuilder = trackBuilder;
		this.signalMode = signalMode;
		this.signalInterval = signalInterval;
	}
	
	function Run() {
		local path = trackBuilder.GetPath();
		Debug("Building signals...");
		local node = path;
		local prev = null;
		local prevprev = null;
		local prevprevprev = null;
		local count = -2;	// don't start with signals right away
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
						count > 0 &&
					    count % this.signalInterval == 0 &&
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
