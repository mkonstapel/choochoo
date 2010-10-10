class Builder extends Task {
	
	relativeCoordinates = null;
	location = null;
	rotation = null;
	
	constructor(parentTask, location, rotation = Rotation.ROT_0) {
		Task.constructor(parentTask);
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}
	
	function GetTile(coordinates) {
		return relativeCoordinates.GetTile(coordinates);
	}
	
	function SetLocalCoordinateSystem(location, rotation) {
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}
	
	/**
	 * Build a non-diagonal segment of track.
	 */
	function BuildSegment(start, end) {
		DoSegment(start, end, true);
	}
	
	/**
	 * Remove a non-diagonal segment of track.
	 */
	function RemoveSegment(start, end) {
		DoSegment(start, end false);
	}
	
	function DoSegment(start, end, build) {
		local from, to;
		if (start[0] == end[0]) {
			from = [start[0], start[1] - 1];
			to = [end[0], end[1] + 1];
		} else {
			from = [start[0] - 1, start[1]];
			to = [end[0] + 1, end[1]];
		}
		
		if (build)
			BuildRail(from, start, to);
		else
			RemoveRail(from, start, to);
	}
	
	/**
	 * Build a straight piece of track, excluding 'from' and 'to'.
	 */
	function BuildRail(from, on, to) {
		AIRail.BuildRail(GetTile(from), GetTile(on), GetTile(to));
		CheckError();
	}
	
	/**
	 * Remove rail, see BuildRail. If a vehicle is in the way, wait and retry.
	 */
	function RemoveRail(from, on, to, check = false) {
		while (true) {
			AIRail.RemoveRail(GetTile(from), GetTile(on), GetTile(to));
			if (AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY) {
				AIController.Sleep(1);
			} else {
				break;
			}
		}
		
		if (check) CheckError();
	}
	
	function BuildSignal(tile, front, type) {
		// if we build a signal again on a tile that already has one,
		// it'll be turned the other way, so check before we build
		if (AIRail.GetSignalType(GetTile(tile), GetTile(front)) == AIRail.SIGNALTYPE_NONE) {
			AIRail.BuildSignal(GetTile(tile), GetTile(front), type);
			CheckError();
		}
	}
	
	function BuildDepot(tile, front) {
		// trying to build a depot where one already exists results in AREA_NOT_CLEAR, not ALREADY_BUILT
		tile = GetTile(tile);
		front = GetTile(front);
		if (AIRail.IsRailDepotTile(tile) && AIRail.GetRailDepotFrontTile(tile) == front) return;
		AIRail.BuildRailDepot(tile, front);
		CheckError();
	}
	
	function BuildRoadDepot(tile, front) {
		tile = GetTile(tile);
		front = GetTile(front);
		if (AIRoad.IsRoadDepotTile(tile) && AIRoad.GetRoadDepotFrontTile(tile) == front) return;
		AIRoad.BuildRoadDepot(tile, front);
		CheckError();
	}
	
	function BuildSign(tile, text) {
		AISign.BuildSign(GetTile(tile), text);
		CheckError();
	}
	
	function Demolish(tile) {
		AITile.DemolishTile(GetTile(tile));
		// CheckError()?
	}
	
	function BuildRoadDriveThrough(tile, front, bus, station = AIStation.STATION_NEW) {
		tile = GetTile(tile);
		front = GetTile(front);
		if (AIRoad.IsDriveThroughRoadStationTile(tile)) return;
		local type = bus ? AIRoad.ROADVEHTYPE_BUS : AIRoad.ROADVEHTYPE_TRUCK;
		AIRoad.BuildDriveThroughRoadStation(tile, front, type, station);
		CheckError();
	}
}