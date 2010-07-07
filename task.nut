require("util.nut");

class TaskFailedException {
	msg = null;
	
	constructor(msg) {
		this.msg = msg;
		Warning(this + " (the following red text is not an actual error)");
	}
	
	function _tostring() {
		return "Task failed: " + msg;
	}
}

class TaskRetryException {
	sleep = 0;
	
	constructor(sleep = 10) {
		this.sleep = sleep;
		Warning(this + " (the following red text is not an actual error)");
	}
	
	function _tostring() {
		return "Retry: " + sleep;
	}
}
class NeedMoneyException {
	
	amount = 0;
	
	constructor(amount) {
		this.amount = amount;
		Warning(this + " (the following red text is not an actual error)");
	}
	
	function _tostring() {
		return "NeedMoney: £" + amount;
	}
}

class Task {
	
	static MAX_ERR_UNKNOWN = 10;
	static MAX_RETRY = 50;
	
	errUnknownCount = 0;
	errRetryCount = 0;
	costEstimate = 5000;
	
	function Run() {
		throw TaskFailedException("task not implemented");
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
				throw errUnknownCount < MAX_ERR_UNKNOWN ? TaskRetryException() : TaskFailedException("too many ERR_UNKNOWN");
							
			case AIError.ERR_NOT_ENOUGH_CASH:
				costEstimate *= 2;
				throw NeedMoneyException(costEstimate);
				
			case AIError.ERR_VEHICLE_IN_THE_WAY:
				errRetryCount++;
				throw errRetryCount < MAX_RETRY ? TaskRetryException() : TaskFailedException("too many retries");
			
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
		RunSubtasks();
	}
	
	function RunSubtasks() {
		while (subtasks.len() > 0) {
			currentTask = subtasks[0];
			Debug("Running subtask: " + currentTask);
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
		
		SubtaskFailed();
	}
	
	function SubtaskFailed() {
		Warning(this + ": subtask failed");
	}
	
	function _tostring() {
		return parentTask + ": (" + ArrayToString(subtasks) + ")";
	}
}

class Marker extends Task {
	
	parentTask = null;
	value = null;
	
	constructor(parentTask, value) {
		this.parentTask = parentTask;
		this.value = value;
	}
	
	function Run() {
		parentTask.Callback(value);
	}
	
	function _tostring() {
		return "Marker " + value;
	}
}