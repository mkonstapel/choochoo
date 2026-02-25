require("util.nut");
require("aystar.nut");
require("pathfinder.nut");
require("world.nut");
require("signs.nut");
require("task.nut");
require("finance.nut");
require("builder.nut");
require("planner.nut");
require("manager.nut");
require("vehicles.nut");
require("tests.nut");

const MIN_DISTANCE =  30;
const MAX_DISTANCE = 100;
const MAX_BUS_ROUTE_DISTANCE = 40;
const INDEPENDENTLY_WEALTHY = 1000000;	// no longer need a loan

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}

// counterclockwise
enum Rotation {
	ROT_0, ROT_90, ROT_180, ROT_270
}

enum SignalMode {
	NONE, FORWARD, BACKWARD, BRANCH
}

class ChooChoo extends AIController {
	
	minMoney = 0;
	year = 0;

	function Start() {
		AICompany.SetName("ChooChoo");
		AICompany.SetAutoRenewStatus(true);
		AICompany.SetAutoRenewMonths(0);
		AICompany.SetAutoRenewMoney(0);
		
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		
		::MAP_SIZE_X <- AIMap.GetMapSizeX();
		::MAP_SIZE_Y <- AIMap.GetMapSizeY();
		::COMPANY <- AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
		::PAX <- GetPassengerCargoID();
		::MAIL <- GetMailCargoID();
		::TICKS_PER_DAY <- 74;
		::SIGN1 <- -1;
		::SIGN2 <- -1;
		::TESTING <- false;
		
		::tasks <- [];

		CheckGameSettings();

		local seed = AIController.GetSetting("RandomSeed");
		if (seed == 0) {
			seed = AIBase.Rand();
		}

		Debug("Random seed:", seed);
		::RANDOM <- Random(seed);

		AIRail.SetCurrentRailType(AIRailTypeList().Begin());
		//CalculateRoutes();

		if (AIController.GetSetting("RunTests") == 1) {
			local towns = AITownList();
			for (local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
				Debug(AITown.GetName(town));
				if (AITown.GetName(town) == "CHOOCHOOTEST") {
					Debug("Running tests");
					::TESTING <- true;
					break;
				}
			}
		}
		
		if (TESTING) {
			tasks.push(RunTests());
		} else if (AIStationList(AIStation.STATION_TRAIN).IsEmpty()) {
			// start with some point to point lines
			tasks.push(Bootstrap());
		}
		
		while (true) {
			// unfortunately, we can't re-throw an exception and get a stack trace
			// if we've caught it, so we run the main loop either inside a try/catch,
			// or not, based on the CarryOn setting

			if (AIController.GetSetting("CarryOn") == 0) {
				// safety off, debugging on
				MainLoop();
			} else {
				try {
					MainLoop();
				} catch (e) {
					Error("Unexpected error: " + e);
					Warning("To capture a stack trace, disable \"Keep running on unexpected errors\" in the AI settings.");
					Warning("This will terminate the AI company, but will help the developer fix the bug!");
					// sleep on it and hope it goes away
					Sleep(TICKS_PER_DAY);
				}
			}
		}
	}

	function MainLoop() {
		HandleEvents();
		
		if (year != AIDate.GetYear(AIDate.GetCurrentDate())) {
			year = AIDate.GetYear(AIDate.GetCurrentDate());
			try {
				CullTrains();
			} catch (e) {
				Error("Error culling trains: " + e);
			}
		}

		if (tasks.len() == 0) {
			tasks.push(BuildNewNetwork(null));
		}
		
		Debug("Tasks: " + ArrayToString(tasks));
		
		local task;
		try {
			if (minMoney > 0) WaitForMoney(minMoney);
			minMoney = 0;
			
			// run the next task in the queue
			task = tasks[0];
			Debug("Running: " + task);
			task.Run();
			tasks.remove(0);
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
				} else if (e instanceof TooManyVehiclesException) {
					// TODO cull more aggressively?
					// we don't to keep building and failing each task because we can't build trains
					// so instead, just continue building, but slow down?
					Warning("Reached max number of vehicles, sleeping for 30 days");
					Sleep(30*TICKS_PER_DAY);
				} else {
					throw e;
				}
			} else if (typeof(e) == "string") {
				if (AIController.GetSetting("CarryOn") == 0) {
					Error("Programming error:", e);
					Error("Rerunning last task to obtain a stack trace");

					// These are things like "the index 'foo' does not exist" due to programming errors.
					// Rethrowing the string loses the original stack trace, making it impossible to debug
					// so we run the failing task again to get a proper stack trace
					task.Run();
				} else {
					throw e;
				}
			} else {
				Error("Unknown error type:", typeof(e));
				throw e;
			}
		}
	}
	
	function WaitForMoney(amount) {
		local reserve = GetMinimumSafeMoney();
		local autorenew = GetAutoRenewMoney();
		local total = amount + reserve + autorenew;
		
		Debug("Waiting until we have £" + total + " (£" + amount + " to spend plus £" + reserve + " in reserve and £" + autorenew + " for autorenew)");
		MaxLoan();
		while (GetBankBalance() < amount) {
			local percentage = (100 * GetBankBalance()) / total;
			local bar = "";
			for (local i = 0; i < 100; i += 10) {
				if (percentage > i) {
					bar += "I";
				} else {
					bar += ".";
				}
			}
			
			// maximum sign length is 30 characters; pound sign seems to require two (bytes?)
			local currency = total >= 100000 ? "" : "£";
			SetSecondarySign("Money: need " + currency + total/1000 + "K [" + bar + "]");
			
			FullyMaxLoan();
			HandleEvents();
			Sleep(TICKS_PER_DAY);
			MaxLoan();
		}
		
		ClearSecondarySign();
	}
	
	function HandleEvents() {
		while (AIEventController.IsEventWaiting()) {
  			local e = AIEventController.GetNextEvent();
  			local converted;
  			local vehicle;
  			switch (e.GetEventType()) {
  				case AIEvent.AI_ET_VEHICLE_UNPROFITABLE:
  					converted = AIEventVehicleUnprofitable.Convert(e);
  					vehicle = converted.GetVehicleID();
  					Cull(vehicle);
  					break;
  					
				case AIEvent.AI_ET_VEHICLE_WAITING_IN_DEPOT:
					converted = AIEventVehicleWaitingInDepot.Convert(e);
					vehicle = converted.GetVehicleID();
					Warning("Selling: " + AIVehicle.GetName(vehicle));
					AIVehicle.SellVehicle(vehicle);
					break;
				
      			default:
      				// Debug("Unhandled event:" + e);
  			}
		}
	}
	
	function CheckGameSettings() {
		local ok = true;
		ok = CheckSetting("construction.road_stop_on_town_road", 1,
			"Advanced Settings, Stations, Allow drive-through road stations on town owned roads") && ok;
		ok = CheckSetting("station.distant_join_stations", 1,
			"Advanced Settings, Stations, Allow to join stations not directly adjacent") && ok;
		
		if (ok) {
			Debug("Game settings OK");
		} else {
			throw "ChooChoo is not compatible with current game settings.";
		}

		if (PAX == null) {
			throw "ChooChoo cannot run without passengers as a cargo type.";
		}
	}
	
	function CheckSetting(name, value, description) {
		if (!AIGameSettings.IsValid(name)) {
			Warning("Setting " + name + " does not exist! ChooChoo may not work properly.");
			return true;
		}
		
		local gameValue = AIGameSettings.GetValue(name);
		if (gameValue == value) {
			return true;
		} else {
			Warning(name + " is " + (gameValue ? "on" : "off"));
			Warning("You can change this setting under " + description);
			return false;
		}
	}
	
	function Save() {
		return {};
	}

	function Load(version, data) {}
}

class Bootstrap extends Task {
	
	function _tostring() {
		return "Bootstrap";
	}
	
	function Run() {
		for (local i = 0; i < AIController.GetSetting("CargoLines"); i++) {
			tasks.push(BuildCargoLine());
		}
	}
	
}