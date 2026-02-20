const MONTHLY_STATION_MAINTENANCE = 50;	// station upkeep per month

function GetBankBalance() {
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	return AICompany.GetBankBalance(me);
}

function GetAvailableMoney() {
	// how much we have, plus how much we can borrow
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	return AICompany.GetBankBalance(me) + AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount();
}

function MaxLoan() {
	// since we can't (accidentally) spend money that's not in our bank balance,
	// keep enough available in the form of loanable money to avoid bankrupcy
	local safetyIntervals = Ceiling(GetMinimumSafeMoney().tofloat()/AICompany.GetLoanInterval());
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	if (AICompany.GetBankBalance(me) < INDEPENDENTLY_WEALTHY) {
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount() - safetyIntervals * AICompany.GetLoanInterval());
	} else {
		AICompany.SetLoanAmount(0);
	}
}

/**
 * Max out our loan, including the amount kept in reserve for paying station maintenance.
 * Make sure you don't spend it!
 */
function FullyMaxLoan() {
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
}

function ManageLoan() {
	// repay loan
	// if we dip below our MinimumSafeMoney, we'll extend the loan up to its maximum,
	// but the AI must take care not to spend this extra cash!
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	local balance = AICompany.GetBankBalance(me) - GetMinimumSafeMoney();
	local balanceMod = (balance / AICompany.GetLoanInterval()) * AICompany.GetLoanInterval();
	local loan = AICompany.GetLoanAmount();

	if (balance < 0) {
		// not good... we lost money?
		FullyMaxLoan();
		balance = AICompany.GetBankBalance(me) - GetMinimumSafeMoney();
		balanceMod = (balance / AICompany.GetLoanInterval()) * AICompany.GetLoanInterval();
		loan = AICompany.GetLoanAmount();
	}

	if (loan > 0 && balanceMod > 0) {
		if (balanceMod >= loan) {
			AICompany.SetLoanAmount(0);
		} else {
			AICompany.SetLoanAmount(loan - balanceMod);
		}
	}
}

/**
 * Keep enough money around for several months of station maintenance and running costs,
 * to prevent bankrupcy.
 */
function GetMinimumSafeMoney() {
	local vehicles = AIVehicleList();
	vehicles.Valuate(AIVehicle.GetRunningCost);
	local runningCosts = Sum(vehicles) / 12;
	local maintenance = AIStationList(AIStation.STATION_ANY).Count() * MONTHLY_STATION_MAINTENANCE;
	local safety = 3*(runningCosts + maintenance);

	// at the start, just risk it
	return safety < 10000 ? 0 : safety;
}

/**
 * See if we need to reserve money for autorenewing trains.
 */
function GetAutoRenewMoney() {
	local vehicles = AIVehicleList();
	vehicles.Valuate(AIVehicle.GetAgeLeft);
	vehicles.KeepBelowValue(366);
	vehicles.Sort(AIList.SORT_BY_VALUE, true);
	for (local vehicle = vehicles.Begin(); vehicles.HasNext(); vehicle = vehicles.Next()) {
		// save money for the next train to be renewed
		// the oldest may no longer be available, in which case GetPrice() returns -1
		local engine = AIVehicle.GetEngineType(vehicle);
		if (AIEngine.IsValidEngine(engine)) {
			return AIEngine.GetPrice(engine);
		}
	}

	return 0;
}
