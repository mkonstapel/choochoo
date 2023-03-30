function SetConstructionSign(tile, task) {
	local mode = AIExecMode();
	AISign.RemoveSign(SIGN1);
	
	if (!AIController.GetSetting("ActivitySigns")) return;
	
	local text = task.tostring();
	local space = text.find(" ");
	if (space) {
		text = text.slice(0, space);
	}
	
	text = "ChooChoo: " + text;
	
	if (text.len() > 30) {
		text = text.slice(0, 29);
	}
	
	SIGN1 = AISign.BuildSign(tile, text);
}

function SetSecondarySign(text) {
	local mode = AIExecMode();
	if (!AIController.GetSetting("ActivitySigns")) {
		AISign.RemoveSign(SIGN2);
		return;
	}
	
	if (text.len() > 30) {
		text = text.slice(0, 29);
	}
	
	local tile = AISign.GetLocation(SIGN1) + AIMap.GetTileIndex(1, 1);
	if (AISign.GetLocation(SIGN2) == tile) {
		AISign.SetName(SIGN2, text);
	} else {
		AISign.RemoveSign(SIGN2);
		SIGN2 = AISign.BuildSign(tile, text);
	}	
}

function ClearSecondarySign() {
	local mode = AIExecMode();
	AISign.RemoveSign(SIGN2);
}
