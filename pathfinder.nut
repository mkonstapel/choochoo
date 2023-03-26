/* $Id: main.nut 15101 2009-01-16 00:05:26Z truebrain $ */

function BuildSign(tile, text) {
	local mode = AIExecMode();
	AISign.BuildSign(tile, text);
}
	
/**
 * A Rail Pathfinder.
 */
class Rail
{
	estimate_multiplier = 1;
	
	// _aystar_class = import("graph.aystar", "", 4);
	_aystar_class = AyStar;
	_max_cost = null;              ///< The maximum cost for a route.
	_cost_tile = null;             ///< The cost for a single tile.
	_cost_diagonal_tile = null;    ///< The cost for a diagonal tile.
	_cost_turn = null;             ///< The cost that is added to _cost_tile if the direction changes.
	_cost_slope = null;            ///< The extra cost if a rail tile is sloped.
	_cost_bridge_per_tile = null;  ///< The cost per tile of a new bridge, this is added to _cost_tile.
	_cost_tunnel_per_tile = null;  ///< The cost per tile of a new tunnel, this is added to _cost_tile.
	_cost_coast = null;            ///< The extra cost for a coast tile.
	_cost_no_adj_rail = null;      ///< The extra cost for no rail in an adjacent tile.
	_cost_adj_obstacle = null;     ///< The extra cost for an obstacle in an adjacent tile.
	_pathfinder = null;            ///< A reference to the used AyStar object.
	_max_bridge_length = null;     ///< The maximum length of a bridge that will be build.
	_max_tunnel_length = null;     ///< The maximum length of a tunnel that will be build.

	cost = null;                   ///< Used to change the costs.
	_running = null;
	_goals = null;
	
	follow = null;

	costCalls = null;
	estimateCalls = null;
	neighbourCalls = null;
	

	constructor()
	{
		::ORTHO_NEIGHBOUR_OFFSETS <- [
			AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)
		];
		::ORTHO_NEIGHBOUR_OFFSETS2 <- [
			AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0),
			AIMap.GetTileIndex(0, 2), AIMap.GetTileIndex(0, -2), AIMap.GetTileIndex(2, 0), AIMap.GetTileIndex(-2, 0)
		];

		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_diagonal_tile = 70;
		this._cost_turn = 50;
		this._cost_slope = 100;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_coast = 20;
		this._cost_no_adj_rail = 0;
		this._cost_adj_obstacle = 0;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;
		this._pathfinder = this._aystar_class(this._Cost, this._Estimate, this._Neighbours, this._CheckDirection, this, this, this, this);
		this._pathfinder._queue_class = AIPriorityQueue;

		this.cost = this.Cost(this);
		this._running = false;
		this.follow = null;

		this.costCalls = 0;
		this.neighbourCalls = 0;
		this.estimateCalls = 0;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source tiles.
	 * @param goals The target tiles.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(sources, goals, ignored_tiles = []) {
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[1], 0xFF, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, this._Cost, this);
			nsources.push(path);
		}
		this._goals = goals;
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
	}

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *  This value should either be -1 for infinite, or > 0. Any other value
	 *  aborts immediatly and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 * @see AyStar::FindPath()
	 */
	function FindPath(iterations);
};

class Rail.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":          this._main._max_cost = val; break;
			case "tile":              this._main._cost_tile = val; break;
			case "diagonal_tile":     this._main._cost_diagonal_tile = val; break;
			case "turn":              this._main._cost_turn = val; break;
			case "slope":             this._main._cost_slope = val; break;
			case "bridge_per_tile":   this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":   this._main._cost_tunnel_per_tile = val; break;
			case "coast":             this._main._cost_coast = val; break;
			case "no_adj_rail":       this._main._cost_no_adj_rail = val; break;
			case "adj_obstacle":      this._main._cost_adj_obstacle = val; break;
			case "max_bridge_length": this._main._max_bridge_length = val; break;
			case "max_tunnel_length": this._main._max_tunnel_length = val; break;
			default: throw("the index '" + idx + "' does not exist");
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":          return this._main._max_cost;
			case "tile":              return this._main._cost_tile;
			case "diagonal_tile":     return this._main._cost_diagonal_tile;
			case "turn":              return this._main._cost_turn;
			case "slope":             return this._main._cost_slope;
			case "bridge_per_tile":   return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":   return this._main._cost_tunnel_per_tile;
			case "coast":             return this._main._cost_coast;
			case "no_adj_rail":       return this._main._cost_no_adj_rail;
			case "adj_obstacle":      return this._main._cost_adj_obstacle;
			case "max_bridge_length": return this._main._max_bridge_length;
			case "max_tunnel_length": return this._main._max_tunnel_length;
			default: throw("the index '" + idx + "' does not exist");
		}
	}

	constructor(main)
	{
		this._main = main;
	}
};

function Rail::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	if (!this._running && ret != null) {
		foreach (goal in this._goals) {
			if (goal[0] == ret.GetTile()) {
				return this._pathfinder.Path(ret, goal[1], 0, this._Cost, this);
			}
		}
	}
	return ret;
}

function Rail::_GetBridgeNumSlopes(end_a, end_b)
{
	local slopes = 0;
	local direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
	local slope = AITile.GetSlope(end_a);
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}

	local slope = AITile.GetSlope(end_b);
	direction = -direction;
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}
	return slopes;
}

function Rail::_nonzero(a, b)
{
	return a != 0 ? a : b;
}

function Rail::_Cost(path, new_tile, new_direction, self)
{
	self.costCalls++;

	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	local prev_tile = path.GetTile();
	local p = path.GetParent();
	local pt = p && p.GetTile();
	local pp = p && p.GetParent();
	local ppt = pp && pp.GetTile();
	local ppp = pp && pp.GetParent();
	local pppt = ppp && ppp.GetTile();

	local diagonal = pt && AIMap.DistanceManhattan(pt, prev_tile) == 1 && pt - prev_tile != prev_tile - new_tile;
	local cost = diagonal ? self._cost_diagonal_tile : self._cost_tile;

	// only check adjacent rail and obstacles if we have to;
	// for the first track we don't care about adjacent rail and for the follower we don't care about obstacles
	if (self._cost_no_adj_rail > 0) {
		local hasNeighbourRail = self.follow.HasItem(new_tile);
		foreach (offset in ORTHO_NEIGHBOUR_OFFSETS) {
			local neighbour = new_tile + offset;
			if (self.follow && self.follow.HasItem(neighbour)) {
				hasNeighbourRail = true;
				break;
			}
		}

		if (!hasNeighbourRail) {
			cost += self._cost_no_adj_rail;
		}
	}

	if (self._cost_adj_obstacle > 0) {
		local hasObstacle = false;
		foreach (offset in ORTHO_NEIGHBOUR_OFFSETS2) {
			local neighbour = new_tile + offset;
			if (!AITile.IsBuildable(neighbour)) {
				hasObstacle = true;
				break;
			}
		}

		if (hasObstacle) {
			cost += self._cost_adj_obstacle;
		}
	}
	
	/* Check if the new tile is a coast tile. */
	if (AITile.IsCoastTile(new_tile)) {
		cost += self._cost_coast;
	}

	/* Check if the last tile was sloped. */
	if (pt && !AIBridge.IsBridgeTile(prev_tile) && !AITunnel.IsTunnelTile(prev_tile) &&
			self._IsSlopedRail(pt, prev_tile, new_tile)) {
		cost += self._cost_slope;
	}

	/* We don't use already existing rail, so the following code is unused. It
	 *  assigns if no rail exists along the route. */
	/*
	if (path.GetParent() != null && !AIRail.AreTilesConnected(path.GetParent().GetTile(), prev_tile, new_tile)) {
		cost += self._cost_no_existing_rail;
	}
	*/

	/* If the new tile is a bridge / tunnel tile, check whether we came from the other
	 *  end of the bridge / tunnel or if we just entered the bridge / tunnel. */
	if (AIBridge.IsBridgeTile(new_tile) &&  AIBridge.GetOtherBridgeEnd(new_tile) == prev_tile) {
		cost += AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile + self._GetBridgeNumSlopes(new_tile, prev_tile) * self._cost_slope;
	}

	if (AITunnel.IsTunnelTile(new_tile) && AITunnel.GetOtherTunnelEnd(new_tile) == prev_tile) {
		cost += AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile;
	}

	/* If the two tiles are more then 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be build. It isn't an existing bridge / tunnel, as that case is already handled. */
	if (AIMap.DistanceManhattan(new_tile, prev_tile) > 1) {
		/* Check if we should build a bridge or a tunnel. */
		if (AITunnel.GetOtherTunnelEnd(new_tile) == prev_tile) {
			cost += AIMap.DistanceManhattan(new_tile, prev_tile) * (self._cost_tile + self._cost_tunnel_per_tile);
		} else {
			cost += AIMap.DistanceManhattan(new_tile, prev_tile) * (self._cost_tile + self._cost_bridge_per_tile) + self._GetBridgeNumSlopes(new_tile, prev_tile) * self._cost_slope;
		}
	}
	
	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	 
	// if we don't have enough parents to determine a turn, assume diagonal is bad
	// because we want to exit straight from stations and crossings
	local long = pp;
	if ((long && self._IsTurn(ppt, pt, prev_tile, new_tile)) ||
		(!long && diagonal)) {
			//AIMap.DistanceManhattan(new_tile, path.GetParent().GetParent().GetTile()) == 3 &&
			//path.GetParent().GetParent().GetTile() - path.GetParent().GetTile() != prev_tile - new_tile) {
		cost += self._cost_turn;
	}
	
	/* Check for a double turn. */
	if (pppt && self._IsTurn(pppt, ppt, pt, prev_tile)) {
		cost += 2*self._cost_turn;
	}
	
	return path.GetCost() + cost;
}

function Rail::_Estimate(cur_tile, cur_direction, goal_tiles, self)
{
	self.estimateCalls++;
	local min_cost = self._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (tile in goal_tiles) {
		local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(tile[0]));
		local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(tile[0]));
		min_cost = min(min_cost, min(dx, dy) * self._cost_diagonal_tile * 2 + (max(dx, dy) - min(dx, dy)) * self._cost_tile);
	}
	
	return min_cost*self.estimate_multiplier;
}

function Rail::_Neighbours(path, cur_node, self)
{
	self.neighbourCalls++;

	// when creating the second rail of a double track, allow non-conflicting
	// rail pieces: NW-NE + SW-SE or NW-SW+NE+SE
	if (self.follow == null && AITile.HasTransportType(cur_node, AITile.TRANSPORT_RAIL)) return [];

	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path.GetCost() >= self._max_cost) return [];
	
	local tiles = [];
	local par = path.GetParent();
	local par_tile = par && par.GetTile();
	/* Check if the current tile is part of a bridge or tunnel. */
	if (AIBridge.IsBridgeTile(cur_node) || AITunnel.IsTunnelTile(cur_node)) {
		/* We don't use existing rails, so neither existing bridges / tunnels. */
	} else if (par != null && AIMap.DistanceManhattan(cur_node, par_tile) > 1) {
		local other_end = par_tile;
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		foreach (offset in ORTHO_NEIGHBOUR_OFFSETS) {
			if (AIRail.BuildRail(cur_node, next_tile, next_tile + offset)) {
				tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true)]);
			}
		}
	} else {
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in ORTHO_NEIGHBOUR_OFFSETS) {
			local next_tile = cur_node + offset;
			/* Don't turn back */
			if (par != null && next_tile == par_tile) continue;
			/* Disallow 90 degree turns */
			if (par != null && par.GetParent() != null &&
				next_tile - cur_node == par.GetParent().GetTile() - par_tile) continue;
			/* We add them to the to the neighbours-list if we can build a rail to them
			without crossing another rail. */
			local buildable = AIRail.BuildRail(par_tile, cur_node, next_tile);
			local tracks = AIRail.GetRailTracks(cur_node);
			if (buildable && tracks != AIRail.RAILTRACK_INVALID) {
				// check if we can build here without creating a crossing
				// using direction logic from _IsSlopedRail
				local NW = cur_node - AIMap.GetMapSizeX() == par_tile || cur_node - AIMap.GetMapSizeX() == next_tile;
				local NE = cur_node - 1 == par_tile || cur_node - 1 == next_tile;
				local SE = cur_node + AIMap.GetMapSizeX() == par_tile || cur_node + AIMap.GetMapSizeX() == next_tile;
				local SW = cur_node + 1 == par_tile || cur_node + 1 == next_tile;
				
				buildable = (
					   NW && NE && tracks == AIRail.RAILTRACK_SW_SE
					|| SW && SE && tracks == AIRail.RAILTRACK_NW_NE
					|| NW && SW && tracks == AIRail.RAILTRACK_NE_SE
					|| NE && SE && tracks == AIRail.RAILTRACK_NW_SW
				);
			}

			if (par == null || buildable) {
				tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
			}
		}
		if (par != null && par.GetParent() != null) {
			local bridges = self._GetTunnelsBridges(par_tile, cur_node, self._GetDirection(par.GetParent().GetTile(), par_tile, cur_node, true));
			foreach (tile in bridges) {
				tiles.push(tile);
			}
		}
	}
	return tiles;
}

function Rail::_CheckDirection(tile, existing_direction, new_direction, self)
{
	return false;
}

function Rail::_dir(from, to)
{
	if (from - to == 1) return 0;
	if (from - to == -1) return 1;
	if (from - to == AIMap.GetMapSizeX()) return 2;
	if (from - to == -AIMap.GetMapSizeX()) return 3;
	throw("Shouldn't come here in _dir");
}

function Rail::_GetDirection(pre_from, from, to, is_bridge)
{
	if (is_bridge) {
		if (from - to == 1) return 1;
		if (from - to == -1) return 2;
		if (from - to == AIMap.GetMapSizeX()) return 4;
		if (from - to == -AIMap.GetMapSizeX()) return 8;
	}
	return 1 << (4 + (pre_from == null ? 0 : 4 * this._dir(pre_from, from)) + this._dir(from, to));
}

/**
 * Get a list of all bridges and tunnels that can be build from the
 *  current tile. Bridges will only be build starting on non-flat tiles
 *  for performance reasons. Tunnels will only be build if no terraforming
 *  is needed on both ends.
 */
function Rail::_GetTunnelsBridges(last_node, cur_node, bridge_dir)
{
	local slope = AITile.GetSlope(cur_node);
	if (slope == AITile.SLOPE_FLAT && AITile.IsBuildable(cur_node + (cur_node - last_node))) return [];
	local tiles = [];

	for (local i = 2; i < this._max_bridge_length; i++) {
		local bridge_list = AIBridgeList_Length(i + 1);
		local target = cur_node + i * (cur_node - last_node);
		if (!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_node, target)) {
			// don't allow the following track to jump over its peer, because it looks ugly
			local ugly = false;
			if (follow) {
				local span = AITileList();
				span.AddRectangle(cur_node, target);
				for (local tile = span.Begin(); span.HasNext(); tile = span.Next()) {
					if (follow.HasItem(tile)) {
						ugly = true;
						break;
					}
				}
			}

			if (!ugly) {
				// only allow bridges if they actually go over unbuildable stuff (like water and rail)?
				// I don't think we need to, now that it builds smaller, less conspicuous bridges
				// local span = AITileList();
				// span.AddRectangle(cur_node, target);
				// span.Valuate(AITile.IsBuildable);
				// span.KeepValue(0);
				// if (span.Count() > 0 && span.Count() > AIMap.DistanceManhattan(cur_node, target) - 4) {
				// 	tiles.push([target, bridge_dir]);
				// 	// break here to only return the shortest possible bridge
				// 	// but with the raised costs, it should be OK to also consider longer bridges
				// 	// break;
				// }

				tiles.push([target, bridge_dir]);
			}
		}
	}

	if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) return tiles;
	local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
	if (!AIMap.IsValidTile(other_tunnel_end)) return tiles;

	local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
	local prev_tile = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
	if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && tunnel_length >= 2 &&
			prev_tile == last_node && tunnel_length < _max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, cur_node)) {
		tiles.push([other_tunnel_end, bridge_dir]);
	}
	return tiles;
}

function Rail::_IsTurn(pre, start, middle, end)
{
	//AIMap.DistanceManhattan(new_tile, path.GetParent().GetParent().GetTile()) == 3 &&
	//path.GetParent().GetParent().GetTile() - path.GetParent().GetTile() != prev_tile - new_tile) {
	return AIMap.DistanceManhattan(end, pre) == 3 && pre - start != middle - end;
}


function Rail::_IsSlopedRail(start, middle, end)
{
	local NW = 0; // Set to true if we want to build a rail to / from the north-west
	local NE = 0; // Set to true if we want to build a rail to / from the north-east
	local SW = 0; // Set to true if we want to build a rail to / from the south-west
	local SE = 0; // Set to true if we want to build a rail to / from the south-east

	if (middle - AIMap.GetMapSizeX() == start || middle - AIMap.GetMapSizeX() == end) NW = 1;
	if (middle - 1 == start || middle - 1 == end) NE = 1;
	if (middle + AIMap.GetMapSizeX() == start || middle + AIMap.GetMapSizeX() == end) SE = 1;
	if (middle + 1 == start || middle + 1 == end) SW = 1;

	/* If there is a turn in the current tile, it can't be sloped. */
	if ((NW || SE) && (NE || SW)) return false;

	local slope = AITile.GetSlope(middle);
	/* A rail on a steep slope is always sloped. */
	if (AITile.IsSteepSlope(slope)) return true;

	/* If only one corner is raised, the rail is sloped. */
	if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_W) return true;
	if (slope == AITile.SLOPE_S || slope == AITile.SLOPE_E) return true;

	if (NW && (slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE)) return true;
	if (NE && (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW)) return true;

	return false;
}
