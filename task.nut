require("util.nut");

class Task {
	
	function Run() {
		throw Task.FAILED;
	}
	
	function CheckError() {
		switch (AIError.GetLastError()) {
			case AIError.ERR_NONE:
			case AIError.ERR_ALREADY_BUILT:
			case AITile.ERR_AREA_ALREADY_FLAT:
				return;
			
			case AIError.ERR_UNKNOWN:
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
				PrintError();
				throw FAILED;
		}
	}
}

class TaskList extends Task {
	
	subtasks = null;
	
	constructor(subtasks) {
		this.subtasks = subtasks;
	}
	
	function Run() {
		while (subtasks.len() > 0) {
			local task = subtasks[0];
			task.Run();
			subtasks.remove(0);
		}
	}
	
	function _tostring() {
		return "(" + ArrayToString(subtasks) + ")";
	}
}

class DebugTask extends Task {
	
	s = null;
	
	constructor(s) {
		this.s = s;
	}
	
	function Run() {
		Debug(this);
	}
	
	function _tostring() {
		return "DebugTask " + s;
	} 
}

class FailTask extends Task {
	function Run() {
		throw TaskResult.FAILED;
	}
}
		