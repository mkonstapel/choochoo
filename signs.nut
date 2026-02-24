function SetConstructionSign(tile, task) {
	local mode = AIExecMode();
	RemoveSign1();
	
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
		RemoveSign2();
		return;
	}
	
	if (text.len() > 30) {
		text = text.slice(0, 29);
	}
	
	local tile = AISign.GetLocation(SIGN1) + AIMap.GetTileIndex(1, 1);
	if (SIGN2 != -1 && AISign.GetLocation(SIGN2) == tile) {
		AISign.SetName(SIGN2, text);
	} else {
		RemoveSign2();
		SIGN2 = AISign.BuildSign(tile, text);
	}	
}

function ClearSecondarySign() {
	local mode = AIExecMode();
	AISign.RemoveSign(SIGN2);
	SIGN2 = -1;
}

function RemoveSign1() {
	if (SIGN1 == -1) return;
	AISign.RemoveSign(SIGN1);
	SIGN1 = -1;
}

function RemoveSign2() {
	if (SIGN2 == -1) return;
	AISign.RemoveSign(SIGN2);
	SIGN2 = -1;
}