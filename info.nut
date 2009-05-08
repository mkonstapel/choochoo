class ChooChoo extends AIInfo {
	function GetAuthor()      { return "Michiel Konstapel"; }
	function GetName()        { return "ChooChoo"; }
	function GetDescription() { return "Muck about with trains"; }
	function GetVersion()     { return 0; }
	function GetDate()        { return "2009-04-14"; }
	function CreateInstance() { return "ChooChoo"; }
	function GetShortName()	  { return "CHOO"; }
}

RegisterAI(ChooChoo());
