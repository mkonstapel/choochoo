require("RailPathFinder.nut");
require("world.nut");
require("task.nut");
require("builder.nut");

const FAILED = "FAILED";
const RETRY = "RETRY";

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}

// counterclockwise
enum Rotation {
	ROT_0, ROT_90, ROT_180, ROT_270
}

class ChooChoo extends AIController {
	
	function Save() {
		AILog.Info("TODO: implement load and save");
		return {};
	}

	function Load() {
		AILog.Info("TODO: implement load and save");
	}

	function Start() {
		AICompany.SetName("ChooChoo");
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
		
		::PAX <- GetPassengerCargoID();
		::TICKS_PER_DAY <- 37;
		::BLOCK_SIZE <- 64;
		
		::world <- World();
		::tasks <- [];
		
		while (true) {
			if (tasks.len() == 0) {
				tasks.push(Bootstrap());
			}
			
			Debug(ArrayToString(tasks));
				
			try {
				local task = tasks[0];
				task.Run();
				tasks.remove(0);
			} catch (e) {
				// TODO: retry after RETRY, but that keeps crashing
				if (e == RETRY) {
					Sleep(1000);
					//while (AICompany.GetBankBalance(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)) < 10000) {
					//	Sleep(1000);
					//}
					
					Debug("Retrying...");
				} else {
					Debug("Removing failed task");
					tasks.remove(0);
				}
			}
		}
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
		local tile;
		
		// tile = 0xEBD3;
		do {
			Debug("" + AIMap.GetMapSize());
			tile = abs(AIBase.Rand()) % AIMap.GetMapSize();
			Debug("" + tile);
		} while (!AITile.IsBuildableRectangle(tile, Crossing.WIDTH*3, Crossing.WIDTH*3));
		
		tile += AIMap.GetTileIndex(Crossing.WIDTH, Crossing.WIDTH);
		
		local network = Network();
		network.railType = AIRailTypeList().Begin();
		AIRail.SetCurrentRailType(network.railType);
		
		tasks.insert(1, TaskList(this, [
			LevelTerrain(tile, Rotation.ROT_0, [-1, -1], [Crossing.WIDTH + 1, Crossing.WIDTH + 1]),
			BuildCrossing(tile, network)
		]));
	}
	
	function _tostring() {
		return "Bootstrap";
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
