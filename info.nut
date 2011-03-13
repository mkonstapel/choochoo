class ChooChoo extends AIInfo {
	function GetAuthor()      { return "Michiel Konstapel"; }
	function GetName()        { return "ChooChoo"; }
	function GetDescription() { return "Muck about with trains"; }
	function GetVersion()     { return 388; }
	function GetDate()        { return "2011-03-13"; }
	function CreateInstance() { return "ChooChoo"; }
	function GetShortName()	  { return "CHOO"; }
	
	function GetSettings() {
	    AddSetting({name = "BootstrapLines", description = "Number of single track, point to point lines to start with", min_value = 0, max_value = 20, easy_value = 5, medium_value = 10, hard_value = 20, custom_value = 5, flags = AICONFIG_INGAME});
	    AddSetting({name = "MaxBridgeLength", description = "Maximum bridge length", min_value = 0, max_value = 40, easy_value = 20, medium_value = 20, hard_value = 20, custom_value = 20, flags = AICONFIG_INGAME});
	    AddSetting({name = "JunctionNames", description = "Name junctions with waypoints", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	    AddSetting({name = "ActivitySigns", description = "Place signs showing what ChooChoo is doing", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN|AICONFIG_INGAME});
	    AddSetting({name = "PathfinderMultiplier", description = "Pathfinder speed: higher values are faster, but less accurate", min_value = 1, max_value = 4, easy_value = 1, medium_value = 2, hard_value = 3, custom_value = 3, flags = AICONFIG_INGAME});
	    AddLabels("PathfinderMultiplier", {_1 = "Slow", _2 = "Medium", _3 = "Fast", _4 = "Very fast"});
	}
}

RegisterAI(ChooChoo());
