class BuildHQ extends Builder {
	
	constructor(parentTask, location) {
		Builder.constructor(parentTask, location);
	}
	
	function _tostring() {
		return "BuildHQ";
	}
	
	function Run() {
		// build our HQ at a four point crossing, if we don't have one yet
		if (HaveHQ()) return;
		
		local crossing = Crossing(location);
		if (crossing.CountConnections() == 4) {
			AICompany.BuildCompanyHQ(GetTile([-1, -1]));
		}
	}	
}

class LevelTerrain extends Builder {
	
	location = null;
	from = null;
	to = null;
	clear = null;
	
	constructor(parentTask, location, rotation, from, to, clear = false) {
		Builder.constructor(parentTask, location, rotation);
		this.from = from;
		this.to = to;
		this.clear = clear;
	}
	
	function Run() {
		SetConstructionSign(location, this);
		
		local tiles = AITileList();
		tiles.AddRectangle(GetTile(from), GetTile(to));
		
		local min = 100;
		local max = 0;
		
		for (local tile = tiles.Begin(); tiles.HasNext(); tile = tiles.Next()) {
			if (AITile.GetMaxHeight(tile) > max) max = AITile.GetMaxHeight(tile);
			if (AITile.GetMinHeight(tile) < min) min = AITile.GetMinHeight(tile);
		}
		
		// prefer rounding up, because foundations can help us raise
		// tiles to the appropriate height
		local targetHeight = (min + max + 1) / 2;
		for (local tile = tiles.Begin(); tiles.HasNext(); tile = tiles.Next()) {
			LevelTile(tile, targetHeight);
			
			// if desired, clear the area, preemptively removing any trees (for town ratings)
			if (clear) AITile.DemolishTile(tile);
		}
	}
	
	function LevelTile(tile, height) {
		// raise or lower each corner of the tile to the target height
		foreach (corner in [AITile.CORNER_N, AITile.CORNER_E, AITile.CORNER_S, AITile.CORNER_W]) {
			while (AITile.GetCornerHeight(tile, corner) < height) {
				AITile.RaiseTile(tile, 1 << corner);
				if (AIError.GetLastError() == AIError.ERR_NONE) {
					// all's well, continue leveling
				} else if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
					// normal error handling: wait for money and retry
					CheckError();
				} else {
					// we can't level the terrain as requested,
					// but because of foundations built on slopes,
					// we may be able to continue, so don't abort the task
					break;
				}
			}
			
			while (AITile.GetCornerHeight(tile, corner) > height) {
				AITile.LowerTile(tile, 1 << corner);
				if (AIError.GetLastError() == AIError.ERR_NONE) {
					// continue
				} else if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) {
					CheckError();
				} else {
					break;
				}
			}
		}
	}
	
	function CheckTerraformingError() {
		switch (AIError.GetLastError()) {
			case AIError.ERR_NONE:
				// all's well
				break;
			case AIError.ERR_NOT_ENOUGH_CASH:
				// normal error handling: wait for money and retry
				CheckError();
				break;
			default:
				// we can't level the terrain as requested,
				// but because of foundations built on slopes,
				// we may be able to continue, so don't abort yet
				break;
		}
	}
	
	function _tostring() {
		return "LevelTerrain";
	}
	
}


class AppeaseLocalAuthority extends Task {
	
	town = null;
	excludeArea = null;
	minTownRating = null;
	
	constructor(parentTask, town, excludeArea = null, minTownRating = AITown.TOWN_RATING_MEDIOCRE) {
		// POOR is the minimum for building a station, but a little margin is probably nice
		// and it only takes an extra 29 trees
		Task.constructor(parentTask);
		this.town = town;
		this.excludeArea = excludeArea;
		this.minTownRating = minTownRating;

		if (minTownRating > AITown.TOWN_RATING_MEDIOCRE) {
			throw TaskFailedException("building trees can only get you up to TOWN_RATING_MEDIOCRE");
		}
	}
	
	function _tostring() {
		return "AppeaseLocalAuthority at " + AITown.GetName(town);
	}
	
	function Run() {
		local location = AITown.GetLocation(town);
		SetConstructionSign(location, this);

		local currentTownRating = AITown.GetRating(town, COMPANY);
		if (currentTownRating == AITown.TOWN_RATING_NONE) {
			// if you have no rating, you start off at GOOD
			currentTownRating = AITown.TOWN_RATING_GOOD
		};

		if (currentTownRating >= minTownRating) {
			// already good
			return;
		}

		// We can't know our exact numeric rating, but we can get a worst case estimate.
		// These are *maximums* from town.h, so APPALLING could be as low as -1000,
		// VERYPOOR is -399 to -200, etc. NONE 
		// RATING_MINIMUM     = -1000,
		// RATING_APPALLING   =  -400,
		// RATING_VERYPOOR    =  -200,
		// RATING_POOR        =     0,
		// RATING_MEDIOCRE    =   200,
		// RATING_GOOD        =   400,
		// RATING_VERYGOOD    =   600,
		// RATING_EXCELLENT   =   800,
		// RATING_OUTSTANDING =  1000,

		local ratings = {}
		ratings[AITown.TOWN_RATING_APPALLING] <- -1000;
		ratings[AITown.TOWN_RATING_VERY_POOR] <- -400;
		ratings[AITown.TOWN_RATING_POOR] <- -200;
		ratings[AITown.TOWN_RATING_MEDIOCRE] <- 0;
		ratings[AITown.TOWN_RATING_GOOD] <- 200;
		ratings[AITown.TOWN_RATING_VERY_GOOD] <- 400;
		ratings[AITown.TOWN_RATING_EXCELLENT] <- 600;
		ratings[AITown.TOWN_RATING_OUTSTANDING] <- 800;
		ratings[AITown.TOWN_RATING_INVALID] <- 0;

		local numericRating = ratings[currentTownRating];
		local minRating = ratings[minTownRating];
		
		// building a tree gets you 7 rep, up to 220 (GOOD)
		// NB: only the *first* tree on a tile that didn't have one improves company rating!
		// https://github.com/OpenTTD/OpenTTD/blob/master/src/tree_cmd.cpp#L433
		local treesNeeded = Ceiling((minRating - numericRating) / 7.0);

		Debug("Need to plant up to", treesNeeded, "trees to go from", numericRating, "to", minRating);
		local deforestFirst = false;

		local area = GetTreeArea(town);
		KeepValidTreeTiles(area);

		local freeTiles = area.Count();
		Debug("Looks like we can plant", freeTiles, "trees");

		local treeTiles = 0;
		
		// if our rating is already really bad, see if we could get away with nuking a bunch of trees so we can replant them
		if (freeTiles < treesNeeded) {
			local area = GetTreeArea(town);
			area.Valuate(AITile.HasTreeOnTile);
			area.KeepValue(1);
			treeTiles = area.Count();
			deforestFirst = true;

			// this will tank our rating, so recalculate
			currentTownRating = AITown.TOWN_RATING_APPALLING;
			numericRating = ratings[currentTownRating];
			treesNeeded = Ceiling((minRating - numericRating) / 7.0);

			Debug("And we can 'reforest' another", treeTiles, "tiles but then we need to plant", treesNeeded);
		}

		if (freeTiles + treeTiles < treesNeeded) {
			throw TaskFailedException("cannot build enough trees to fix rating at " + AITown.GetName(town));
		}

		if (deforestFirst) {
			SetSecondarySign("\"Reforesting\"")
			local trees = GetTreeArea(town);
			trees.Valuate(AITile.HasTreeOnTile);
			trees.KeepValue(1);
			trees.Valuate(AITile.GetDistanceManhattanToTile, location);
			trees.KeepBottom(treesNeeded - freeTiles + 20);  // add a little safety margin
			for (local tile = trees.Begin(); trees.HasNext(); tile = trees.Next()) {
				AITile.DemolishTile(tile);
				CheckError();
			}
		}

		area = GetTreeArea(town);
		KeepValidTreeTiles(area);

		// build from the inside out
		area.Valuate(AITile.GetDistanceSquareToTile, location);
		area.Sort(AIList.SORT_BY_VALUE, true);

		local treesPlanted = 0;
		SetSecondarySign("Planting trees")
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			if (AITile.HasTreeOnTile(tile)) {
				// trees may regrow while we're planting
				continue;
			} else if (AITile.PlantTree(tile) && AITile.HasTreeOnTile(tile)) {
				treesPlanted++;
			} else {
				local error = AIError.GetLastError();
				if (error == AIError.ERR_NOT_ENOUGH_CASH) {
					// trigger the regular handling of "out of money"
					CheckError();
				} else {
					// just continue to the next tile
					Warning(treesPlanted + " Error planting trees:", AIError.GetLastErrorString());
				}
			}

			// stop when we hit our target rating
			local townRating = AITown.GetRating(town, COMPANY);
			if (townRating >= minTownRating) {
				Debug("Stopping tree planting at rating", townRating, "after planting", treesPlanted, "/", treesNeeded, "trees");
				ClearSecondarySign();
				return;
			}
		}

		Warning("Stopping tree planting after loop, planted", treesPlanted, "/", treesNeeded, "trees, rating", AITown.GetRating(town, COMPANY));
		ClearSecondarySign();
	}

	function KeepValidTreeTiles(area) {
		area.Valuate(AITile.IsBuildable);
		area.KeepValue(1);
		// as mentioned, only the first tree counts
		area.Valuate(AITile.HasTreeOnTile);
		area.KeepValue(0);
		// water, road and rail tiles are "buildable", but not for trees
		// this should also filter out bridges as you cannot build trees underneath a bridge
		area.Valuate(AITile.IsWaterTile);
		area.KeepValue(0);
		area.Valuate(AIRoad.IsRoadTile);
		area.KeepValue(0);
		area.Valuate(AIRail.IsRailTile);
		area.KeepValue(0);
		// diagonal cost tiles (half land, half water) cannot have trees, so just exclude all coast tiles
		area.Valuate(AITile.IsCoastTile);
		area.KeepValue(0);
	}
	
	function GetTreeArea(town) {
		local location = AITown.GetLocation(town);
		local distance = GetGameSetting("economy.dist_local_authority", 20);
		local area = AITileList();
		SafeAddRectangle(area, location, distance);
		if (excludeArea) {
			area.RemoveList(excludeArea);
		}
		
		// for tree building, the game just checks `ClosestTownFromTile(current_tile, _settings_game.economy.dist_local_authority)`
		// area.Valuate(AITile.IsWithinTownInfluence, town);
		// area.KeepValue(1);

		area.Valuate(AITile.GetClosestTown);
		area.KeepValue(town);

		return area;
	}
}
