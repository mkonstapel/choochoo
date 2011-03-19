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
	
	constructor(parentTask, town) {
		Task.constructor(parentTask);
		this.town = town;
	}
	
	function _tostring() {
		return "AppeaseLocalAuthority at " + AITown.GetName(town);
	}
	
	function Run() {
		local location = AITown.GetLocation(town);
		SetConstructionSign(location, this);

		local area = GetInfluenceArea(town);
		area.Valuate(AITile.IsBuildable);
		area.KeepValue(1);
		
		// build from the outside in
		area.Valuate(AITile.GetDistanceSquareToTile, location);
		area.Sort(AIList.SORT_BY_VALUE, false);
		
		local countdown = 1000;	// "lots"
		for (local tile = area.Begin(); area.HasNext() && countdown > 0; tile = area.Next()) {
			local rating = AITown.GetRating(town, COMPANY);
			if (rating == AITown.TOWN_RATING_NONE || rating > AITown.TOWN_RATING_POOR) {
				// good enough ("none" will become "very good")
				return;
			}
			
			if (rating == AITown.TOWN_RATING_APPALLING) {
				// don't bother, as this would require hundreds of trees
				Warning("Rating at " + AITown.GetName(town) + " is appalling, not going to try planting trees");
				return;
			}
			
			if (rating >= AITown.TOWN_RATING_POOR) {
				// once we reach poor, the minimum to build a station, try to add some more
				// for slack, in case we "accidentally" hit a tree later...
				countdown = min(countdown, 20);
			}
			
			// we may not plant a tree at all, in which case we'd be looking at the wrong AIError!
			local planted = false;
			while (AITile.PlantTree(tile) && countdown > 0) {
				planted = true;
				countdown--;
			}
			
			if (!planted || AIError.GetLastError() == AIError.ERR_UNKNOWN || AIError.GetLastError() == AIError.ERR_SITE_UNSUITABLE) {
				// no trees planted, too many trees or building on tile, continue
			} else {
				CheckError();
			}
		}
	}
	
	function GetInfluenceArea(town) {
		local location = AITown.GetLocation(town);
		local distance = GetGameSetting("economy.dist_local_authority", 10);
		local area = AITileList();
		SafeAddRectangle(area, location, distance);
		area.Valuate(AITile.GetDistanceManhattanToTile, location);
		area.KeepBelowValue(distance);
		area.Valuate(AITile.GetClosestTown);
		area.KeepValue(town);
		return area;
	}
}
