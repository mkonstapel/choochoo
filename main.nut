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
	NONE, FORWARD, BACKWARD
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
		
		::tasks <- [];

		CheckGameSettings();

		AIRail.SetCurrentRailType(AIRailTypeList().Begin());
		//CalculateRoutes();
		
		if (AIStationList(AIStation.STATION_TRAIN).IsEmpty()) {
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
					Warning("To capture a stack trace, disable \"Keep running on unexpected errors\" in the AI settings (this will kill the AI company)");
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
				} else {
					throw e;
				}
			} else {
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