require("util.nut");

class Task {
	
	static MAX_ERR_UNKNOWN = 10;
	
	errUnknownCount = 0;
	
	function Run() {
		throw Task.FAILED;
	}
	
	function Failed() {}
	
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
				throw errUnknownCount < MAX_ERR_UNKNOWN ? RETRY : FAILED;
							
			case AIError.ERR_NOT_ENOUGH_CASH:
			case AIError.ERR_VEHICLE_IN_THE_WAY:
				PrintError();
				throw RETRY;
			
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
				Error("Task " + this + " failed:");
				PrintError();
				throw FAILED;
		}
	}
}

class TaskList extends Task {
	
	parentTask = null;
	subtasks = null;
	currentTask = null;
	completed = null;
	
	constructor(parentTask, subtasks) {
		this.parentTask = parentTask;
		this.subtasks = subtasks;
		this.currentTask = null;
		this.completed = [];
	}
	
	function Run() {
		while (subtasks.len() > 0) {
			currentTask = subtasks[0];
			currentTask.Run();
			subtasks.remove(0);
			completed.append(currentTask);
			currentTask = null;
		}
	}
	
	function Failed() {
		foreach (task in completed) {
			task.Failed();
		}
		
		if (currentTask) {
			currentTask.Failed();
		}
	}
	
	function _tostring() {
		return parentTask + ": (" + ArrayToString(subtasks) + ")";
	}
}