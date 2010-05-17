require("pathfinder.nut");
require("world.nut");
require("task.nut");
require("finance.nut");
require("builder.nut");

import("pathfinder.road", "RoadPathFinder", 3);
// TODO: rail pathfinder

const MIN_DISTANCE =  20;
const MAX_DISTANCE = 100;
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
	
	function Start() {
		AICompany.SetName("ChooChoo");
		AICompany.SetAutoRenewStatus(true);
		AICompany.SetAutoRenewMonths(0);
		AICompany.SetAutoRenewMoney(INDEPENDENTLY_WEALTHY);
		
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		AIRail.SetCurrentRailType(AIRailTypeList().Begin());
		
		::PAX <- GetPassengerCargoID();
		::MAIL <- GetMailCargoID();
		::TICKS_PER_DAY <- 37;
		
		::tasks <- [];
		
		if (AIStationList(AIStation.STATION_TRAIN).IsEmpty()) {
			// start with some point to point lines
			tasks.push(Bootstrap());
		}
		
		local minMoney = 0;
		while (true) {
			HandleEvents();
			
			if (tasks.len() == 0) {
				tasks.push(BuildNewNetwork());
			}
			
			Debug("Tasks: " + ArrayToString(tasks));
			
			local task;
			try {
				WaitForMoney(minMoney);
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
					}
				} else {
					Error("Unexpected error");
					return;
				}
			}
		}
	}
	
	function WaitForMoney(amount) {
		local reserve = GetMinimumSafeMoney();
		local total = amount + reserve;
		Debug("Waiting until we have £" + total + " (£" + amount + " to spend plus £" + reserve + " in reserve)");
		MaxLoan();
		while (GetBankBalance() < amount) {
			FullyMaxLoan();
			Sleep(100);
			MaxLoan();
		}
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
  					// see if it's not already going to a depot
  					if (AIOrder.IsGotoDepotOrder(vehicle, AIOrder.ORDER_CURRENT)) {
  						Warning("Vehicle already going to depot");
  					} else {
  						Warning("Vehicle unprofitable: " + AIVehicle.GetName(vehicle));
  						AIVehicle.SendVehicleToDepot(vehicle);
  					}
  					
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
		tasks.push(BuildLine());
		tasks.push(BuildLine());
		tasks.push(BuildLine());
	}
	
}