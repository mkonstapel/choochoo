require("pathfinder.nut");
require("world.nut");
require("task.nut");
require("finance.nut");
require("builder.nut");

import("pathfinder.road", "RoadPathFinder", 3);
// TODO: rail pathfinder

const MIN_DISTANCE =  20;
const MAX_DISTANCE = 100;

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}

// counterclockwise
enum Rotation {
	ROT_0, ROT_90, ROT_180, ROT_270
}

enum SignalMode {
	NONE, FORWARD, BACKWARD
}

class ChooChoo extends AIController {
	
	function Start() {
		AICompany.SetName("ChooChoo");
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		AIRail.SetCurrentRailType(AIRailTypeList().Begin());
		
		::PAX <- GetPassengerCargoID();
		::MAIL <- GetMailCargoID();
		::TICKS_PER_DAY <- 37;
		
		::world <- World();
		::tasks <- [];
		
		// start with some point to point lines
		tasks.push(Bootstrap());
		
		local minMoney = 0;
		while (true) {
			ManageLoan();
			
			if (tasks.len() == 0) {
				tasks.push(BuildNewNetwork());
			}
			
			Debug(ArrayToString(tasks));
			
			// thrown exceptions make lots of red noise in the debug log,
			// so allow tasks to either throw their result if convenient,
			// or return it normally if possible
			local task;
			local result;
			try {
				WaitForMoney(minMoney);
				minMoney = 0;
				
				// run the next task in the queue
				task = tasks[0];
				result = task.Run();
			} catch (e) {
				result = e;
			}
			
			if (result != null && typeof(result) != "instance") {
				Error("Unexpected error");
				return;
			}
			
			if (result == null) {
				tasks.remove(0);
			} else if (result instanceof Retry) {
				Debug("Sleeping...");
				Sleep(result.sleep);
				Debug("Retrying...");
			} else if (result instanceof TaskFailed) {
				Warning(task + " failed: " + result);
				tasks.remove(0);
				task.Failed();
			} else if (result instanceof NeedMoney) {
				Debug(task + " needs £" + result.amount);
				minMoney = result.amount;
			}
		}
	}
	
	function WaitForMoney(amount) {
		Debug("Waiting until we have £" + amount + " to spend plus £" + GetMinimumSafeMoney() + " in reserve");
		MaxLoan();
		while (GetBankBalance() < amount) {
			FullyMaxLoan();
			Sleep(100);
			MaxLoan();
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

class Bootstrap extends Task {
	
	function _tostring() {
		return "Bootstrap";
	}
	
	function Run() {
		tasks.insert(1, TaskList(this, [
			BuildLine(),
			BuildLine(),
			BuildLine(),
		]));
	}
	
}