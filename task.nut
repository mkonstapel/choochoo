require("util.nut");

class TaskFailedException {
	msg = null;
	
	constructor(msg) {
		this.msg = msg;
		Warning(this);
	}
	
	function _tostring() {
		return "Task failed: " + msg;
	}
}

class TaskRetryException {
	sleep = 0;
	
	constructor(sleep = 10) {
		this.sleep = sleep;
		Warning(this);
	}
	
	function _tostring() {
		return "Retry: " + sleep;
	}
}

class NeedMoneyException {
	
	amount = 0;
	
	constructor(amount) {
		this.amount = amount;
		Warning(this);
	}
	
	function _tostring() {
		return "NeedMoney: £" + amount;
	}
}

class TooManyVehiclesException {
	
	trains = 0;
	road = 0;
	
	constructor() {
		Warning(this);
	}
	
	function _tostring() {
		return "TooManyVehicles";
	}
}

class Task {
	
	static MAX_ERR_UNKNOWN = 10;
	static MAX_RETRY = 50;
	
	errUnknownCount = 0;
	errRetryCount = 0;
	costEstimate = 5000;
	
	parentTask = null;
	subtasks = null;
	currentTask = null;
	completed = null;
	
	constructor(parentTask=null, subtasks=null) {
		this.parentTask = parentTask;
		this.subtasks = subtasks;
		this.currentTask = null;
		this.completed = [];
	}
	
	function Run() {
		RunSubtasks();
	}
	
	function GetDepth() {
		if (parentTask == this) {
			throw "Task can't be its own parent! " + this;
		}
		
		return parentTask == null ? 0 : 1 + parentTask.GetDepth();
	}
	
	function RunSubtasks() {
		if (completed == null) throw "Task " + this + " failed to call a parent constructor!";
		
		while (subtasks.len() > 0) {
			currentTask = subtasks[0];
			local indent = StringN(" ", 3*GetDepth());
			Debug(indent + " - " + currentTask);
			currentTask.Run();
			subtasks.remove(0);
			completed.append(currentTask);
			currentTask = null;
		}
	}
	
	function Failed() {
		// fail all completed subtasks, and the current one
		if (completed != null) {
			foreach (task in completed) {
				task.Failed();
			}
		}
		
		if (currentTask) {
			currentTask.Failed();
		}
	}
	
	function _tostring() {
		local s = "Task";
		if (subtasks) s += ": (" + ArrayToString(subtasks) + ")";
		return s;
	}
	
	function CheckError() {
		switch (AIError.GetLastError()) {
			case AIError.ERR_NONE:
			case AIError.ERR_ALREADY_BUILT:
			case AITile.ERR_AREA_ALREADY_FLAT:
				return;

			case AIError.ERR_UNKNOWN:
				errUnknownCount++
				PrintError();
				Warning("ERR_UNKNOWN #" + errUnknownCount);
				throw errUnknownCount < MAX_ERR_UNKNOWN ? TaskRetryException() : TaskFailedException("too many ERR_UNKNOWN");
							
			case AIError.ERR_NOT_ENOUGH_CASH:
				costEstimate *= 2;
				throw NeedMoneyException(costEstimate);
				
			case AIError.ERR_VEHICLE_IN_THE_WAY:
				errRetryCount++;
				throw errRetryCount < MAX_RETRY ? TaskRetryException() : TaskFailedException("too many retries");

			case AIVehicle.ERR_VEHICLE_TOO_MANY:
				throw TooManyVehiclesException();
			
			case AIError.ERR_PRECONDITION_FAILED:
			case AIError.ERR_PRECONDITION_STRING_TOO_LONG:
			case AIError.ERR_NEWGRF_SUPPLIED_ERROR:
			case AIError.ERR_LOCAL_AUTHORITY_REFUSES:
			case AIError.ERR_AREA_NOT_CLEAR:
			case AIError.ERR_OWNED_BY_ANOTHER_COMPANY:
			case AIError.ERR_NAME_IS_NOT_UNIQUE:
			case AIError.ERR_FLAT_LAND_REQUIRED:
			case AIError.ERR_LAND_SLOPED_WRONG:
			case AIError.ERR_SITE_UNSUITABLE:
			case AIError.ERR_TOO_CLOSE_TO_EDGE:
			case AIError.ERR_STATION_TOO_SPREAD_OUT:
			default:
				throw TaskFailedException(AIError.GetLastErrorString());
		}
	}
}

class WaitForMoney extends Task {
	
	parentTask = null;
	amount = null;
	
	constructor(parentTask, amount) {
		Task.constructor(parentTask);
		this.amount = amount;
	}
	
	function Run() {
		if (GetBankBalance() < amount) {
			throw NeedMoneyException(amount);
		}
	}
	
	function _tostring() {
		return "WaitForMoney " + amount;
	}
}

class Marker extends Task {
	
	parentTask = null;
	value = null;
	
	constructor(parentTask, value) {
		Task.constructor(parentTask);
		this.value = value;
	}
	
	function Run() {
		parentTask.Callback(value);
	}
	
	function _tostring() {
		return "Marker " + value;
	}
}