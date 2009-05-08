require("RailPathFinder.nut");
require("world.nut");
require("task.nut");
require("builder.nut");

const FAILED = "FAILED";
const RETRY = "RETRY";

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}
	
class ChooChoo extends AIController {
	
	function Save() {
		// TODO
		return {};
	}

	function Load() {
		AILog.Info("TODO: implement load and save");
	}

	function Start() {
		AICompany.SetName("ChooChoo");
		AIRail.SetCurrentRailType(AIRailTypeList().Begin());
		
		while (true) {
			Debug("Place crossing");
			local sign = FindSign("x");
			local tile = AISign.GetLocation(sign);
			AISign.RemoveSign(sign);
			
			local crossing = BuildCrossing(tile);
			crossing.Run();
			local rotations = [ ROT_270, ROT_180, ROT_90, ROT_0 ];
			
			foreach (index, direction in [Direction.NE, Direction.SE, Direction.SW, Direction.NW]) {
				Debug("Place station");
				sign = FindSign("x");
				tile = AISign.GetLocation(sign);
				AISign.RemoveSign(sign);
				
				local rotation = rotations[index];
				LevelTerrain(tile, rotation, [0,0], [1,5]).Run();
				
				local station = BuildTerminusStation(tile, rotation);
				station.Run();
				
				local reserved = station.GetReservedEntranceSpace();
				reserved.extend(crossing.GetReservedExitSpace(direction));
				BuildTrack(station.GetExit(), crossing.GetEntrance(direction), reserved).Run();
				
				reserved = station.GetReservedExitSpace();
				reserved.extend(crossing.GetReservedEntranceSpace(direction));
				BuildTrack(crossing.GetExit(direction), station.GetEntrance(), reserved).Run();
			}
		}
		
		
		::tasks <- [];
		tasks.append(Bootstrap());
		tasks.append(Expand());
		
		while (tasks.len() > 0) {
			Debug(ArrayToString(tasks));
			
			try {
				local task = tasks[0];
				task.Run();
				tasks.remove(0);
			} catch (e) {
				Debug(e);
			}
		}
		
		Debug("Task queue empty");
		while (true) Sleep(1000);
	}
	
	function DrawCompass() {
		local tile = AIMap.GetTileIndex(10, 10);
		AISign.BuildSign(Step(tile, Direction.N), "N");
		AISign.BuildSign(Step(tile, Direction.E), "E");
		AISign.BuildSign(Step(tile, Direction.S), "S");
		AISign.BuildSign(Step(tile, Direction.W), "W");
		AISign.BuildSign(Step(tile, Direction.NW), "NW");
		AISign.BuildSign(Step(tile, Direction.NE), "NE");
		AISign.BuildSign(Step(tile, Direction.SW), "SW");
		AISign.BuildSign(Step(tile, Direction.SE), "SE");
	}
	
}

class Bootstrap extends Task {
	function Run() {
		Debug("Select site for first crossing");
		local sign = FindSign("x");
		local tile = AISign.GetLocation(sign);
		AISign.RemoveSign(sign);
		
		tasks.insert(1, TaskList([
			LevelTerrain(tile, [5,5]),
			BuildCrossing(tile),
			ExtendCrossing(tile, null),
		]));
	}
	
	function _tostring() {
		return "Bootstrap";
	}
}

class Expand extends Task {
	function Run() {
		Debug("Select site for station");
		local sign = FindSign("x");
		local tile = AISign.GetLocation(sign);
		AISign.RemoveSign(sign);
		
		tasks.insert(1, TaskList(
		[
			//LevelTerrain(tile, [2,5]),
			//BuildStation(tile)
		]));
	}
	
	function _tostring() {
		return "Expand";
	}
}

function FindSign(name) {
	while (true) {
		for (local i = 0; i <= AISign.GetMaxSignID(); i++) {
			if (AISign.IsValidSign(i) && AISign.GetName(i) == name) {
				Debug("Found: " + name);
				return i;
			}
		}
		
		AIController.Sleep(1);
	}
}
