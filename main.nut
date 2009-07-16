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
			
			if (tasks.len() == 0) {
				tasks.push(BuildNewNetwork());
			}
			
			Debug(ArrayToString(tasks));
			
			local task;
			try {
				WaitForMoney(minMoney);
				minMoney = 0;
				
				// run the next task in the queue
				task = tasks[0];
				task.Run();
				tasks.remove(0);
				
				// repay loan if possible
				ManageLoan();
			} catch (e) {
				if (typeof(e) == "instance") {
					if (e instanceof TaskRetryException) {
						Sleep(e.sleep);
						Debug("Retrying...");
					} else if (e instanceof TaskFailedException) {
						Warning(task + " failed: " + e);
						tasks.remove(0);
						task.Failed();
					} else if (e instanceof NeedMoneyException) {
						Debug(task + " needs £" + e.amount);
						minMoney = e.amount;
					}
				} else {
					Error("Unexpected error");
					return;
				}
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