require("pathfinder.nut");
require("world.nut");
require("task.nut");
require("builder.nut");

const FAILED = "FAILED";
const RETRY = "RETRY";
const FATAL = "FATAL";

const BLOCK_SIZE = 64;

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}

// counterclockwise
enum Rotation {
	ROT_0, ROT_90, ROT_180, ROT_270
}

class ChooChoo extends AIController {
	
	function Start() {
		AICompany.SetName("ChooChoo");
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		
		::PAX <- GetPassengerCargoID();
		::MAIL <- GetMailCargoID();
		::TICKS_PER_DAY <- 37;
		
		::world <- World();
		::tasks <- [];
		
		while (true) {
			if (tasks.len() == 0) {
				// build cheap networks until we have 4 stations
				tasks.push(NewNetwork(BLOCK_SIZE, world.stations.len() < 4));
			}
			
			Debug(ArrayToString(tasks));
			
			local task;
			try {
				task = tasks[0];
				task.Run();
				tasks.remove(0);
			} catch (e) {
				if (e == RETRY) {
					// minimum sleep
					Sleep(100);
					
					// retries are usually due to running out of money
					while (AICompany.GetBankBalance(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)) < 20000) {
						Sleep(100);
					}
					
					Debug("Retrying...");
				} else if (e == FAILED) {
					Debug("Removing failed task");
					tasks.remove(0);
					task.Failed();
				} else {
					Error("Unexpected error");
					return;
				}
			}
		}
	}
	
	function Save() {
		Warning("TODO: implement load and save");
		return {};
	}

	function Load() {
		Warning("TODO: implement load and save");
	}
}
