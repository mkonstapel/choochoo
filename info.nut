class ChooChoo extends AIInfo {
	function GetAuthor()      { return "Michiel Konstapel"; }
	function GetName()        { return "ChooChoo"; }
	function GetDescription() { return "Build nice looking train networks"; }
	function GetVersion()     { return 424; }
	function GetDate()        { return "2024-02-23"; }
	function CreateInstance() { return "ChooChoo"; }
	function GetShortName()	  { return "CHOO"; }
	function GetAPIVersion()  { return "1.0"; }
	function GetURL()         { return "https://www.tt-forums.net/viewtopic.php?t=44225"; }
	
	function GetSettings() {
	    AddSetting({name = "CargoLines", description = "Number of single track cargo lines to start with", min_value = 0, max_value = 20, easy_value = 5, medium_value = 10, hard_value = 20, custom_value = 10, flags = AICONFIG_INGAME});
	    AddSetting({name = "MaxBridgeLength", description = "Maximum bridge length", min_value = 0, max_value = 40, easy_value = 20, medium_value = 20, hard_value = 20, custom_value = 20, flags = AICONFIG_INGAME});
	    AddSetting({name = "JunctionNames", description = "Name junctions with waypoints", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	    AddSetting({name = "ActivitySigns", description = "Place signs showing what ChooChoo is doing", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	    AddSetting({name = "PrettyBridges", description = "Prefer looks over speed when selecting bridge types (for example, no cantilever bridges)", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	    AddSetting({name = "TrainTrafficSide", description = "Trains on double track", min_value = 0, max_value = 2, easy_value = 0, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_INGAME});
	    AddLabels("TrainTrafficSide", {_0 = "Drive on same side as road vehicles", _1 = "Drive on left", _2 = "Drive on right"});
	    AddSetting({name = "PathfinderMultiplier", description = "Pathfinder speed: higher values are faster, but maybe messier", min_value = 1, max_value = 4, easy_value = 1, medium_value = 2, hard_value = 3, custom_value = 3, flags = AICONFIG_INGAME});
	    AddLabels("PathfinderMultiplier", {_1 = "Slow", _2 = "Medium", _3 = "Fast", _4 = "Very fast"});
	    AddSetting({name = "CarryOn", description = "Keep running on unexpected errors (rather than aborting with a stack trace)", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	}
}

RegisterAI(ChooChoo());
