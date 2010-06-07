class BuildHQ extends Builder {
	
	constructor(location) {
		Builder.constructor(location);
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
	
	constructor(location, rotation, from, to) {
		Builder.constructor(location, rotation);
		this.from = from;
		this.to = to;
	}
	
	function Run() {
		MoveConstructionSign(location, this);
		
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
	
	constructor(town) {
		this.town = town;
	}
	
	function _tostring() {
		return "AppeaseLocalAuthority";
	}
	
	function Run() {
		local location = AITown.GetLocation(town);
		MoveConstructionSign(location, this);
		
		local area = AITileList();
		SafeAddRectangle(area, location, 20);
		area.Valuate(AITile.IsWithinTownInfluence, town);
		area.KeepValue(1);
		area.Valuate(AITile.IsBuildable);
		area.KeepValue(1);
		
		local rating = AITown.GetRating(town, COMPANY);
		for (local tile = area.Begin(); area.HasNext(); tile = area.Next()) {
			if (rating > -200) {
				break;
			}
			
			AITile.PlantTree(tile);
			if (AIError.GetLastError() == AIError.ERR_UNKNOWN) {
				// too many trees on tile, continue
			} else {
				CheckError();
			}
		}
	}
}
