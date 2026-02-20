const DAYS_PER_MONTH = 30.0;
const DAYS_PER_YEAR = 365.0;
const MAX_CARGO_DISTANCE = 200;

class CargoRoute {
	from = null;
	to = null;
	cargo = null;
	distance = null;
	engine = null;
	wagon = null;
	payback = null;

	constructor(from, to, cargo) {
		this.from = from;
		this.to = to;
		this.cargo = cargo;
		this.engine = GetEngine(cargo, AIRail.GetCurrentRailType(), [], false);
		this.wagon = GetWagon(cargo, AIRail.GetCurrentRailType())
		this.distance = AIMap.DistanceManhattan(AIIndustry.GetLocation(from), AIIndustry.GetLocation(to));
		//this.value = GetDailyProfit() / GetCost();

		//Debug(AICargo.GetCargoLabel(cargo) + " from " + AIIndustry.GetName(from) + " to " + AIIndustry.GetName(to))
		this.payback = GetCost() / GetDailyProfit();
	}

	function GetCost() {
		return GetTrackCost() + GetTrainCost() + GetStationCost();
	}

	function GetTrackCost() {
		return 500 * distance;
	}

	function GetTrainCost() {
		// TODO: calculate optimal train length
		local numWagons = 5;
		return AIEngine.GetPrice(engine) + numWagons * AIEngine.GetPrice(wagon);
	}

	function GetStationCost() {
		return 2000;
	}

	function GetDailyProfit() {
		// TODO: calculate optimal train length
		local numWagons = 5;

		local tripTime = GetTripTime();
		//Debug("Trip time", tripTime);
		local unitIncome = AICargo.GetCargoIncome(cargo, distance, tripTime.tointeger());
		//Debug("Unit Income", unitIncome);
		local carriedUnits = (AIEngine.GetCapacity(wagon) * numWagons) / tripTime;
		local producedUnits = AIIndustry.GetLastMonthProduction(from, cargo) / DAYS_PER_MONTH;
		local units = Min(carriedUnits, producedUnits);
		//Debug(units, "units");
		return (unitIncome * units) - (AIEngine.GetRunningCost(engine)/DAYS_PER_YEAR);
	}

	function GetTripTime() {
		// convert listed speed in km/h to tiles per day
		// vehicles won't drive at full speed the whole route (not even close),
		// so estimate them at half their top speed
		local tilesPerDay = (5.6/100) * AIEngine.GetMaxSpeed(engine)/2;
		local loadingTime = 14;	// number of days to load and unload

		// if breakdowns are enabled, long routes are "more worse" because of the reliability drop
		local breakdowns = AIGameSettings.GetValue("difficulty.vehicle_breakdowns");
		if (breakdowns) {
			// TODO
			tilesPerDay /= 2;
		}

		// other factors: acceleration model, height difference

		return loadingTime + (distance*2)/tilesPerDay;
	}

	function _tostring() {
		return AICargo.GetCargoLabel(cargo) + " from " + AIIndustry.GetName(from) + " to " + AIIndustry.GetName(to) + ": " +
			payback + " days to break even";
	}
}

function CompareRouteValue(a, b) {
	return a.payback - b.payback;
}

function CalculateRoutes() {
	local routes = GenerateRoutes();

	Debug("Found " + routes.len() + " possible cargo routes");

	// convert to an AIList for efficiently finding the best N
	local list = AIList();
	for (local i = 0; i < routes.len(); i++) {
		list.AddItem(i, routes[i].payback.tointeger());
	}

	list.KeepBottom(50);
	list.Sort(AIList.SORT_BY_VALUE, true);

	local best = []
	foreach (index, _ in list) {
		best.append(routes[index]);
	}

	Debug("Best:");
	foreach (route in best) {
		Debug(route);
	}

	return best;
}

function GenerateRoutes() {
	local cargoList = AICargoList();

	// no passengers or mail
	foreach (cc in [AICargo.CC_PASSENGERS, AICargo.CC_MAIL, AICargo.CC_EXPRESS]) {
		cargoList.Valuate(AICargo.HasCargoClass, cc);
		cargoList.KeepValue(0);
	}

	if (cargoList.IsEmpty()) {
		return []
	}

	local routes = [];
	foreach (cargo, _ in cargoList) {
		local consumers = AIIndustryList_CargoAccepting(cargo);
		local producers = AIIndustryList_CargoProducing(cargo);

		producers.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		producers.KeepAboveValue(0);

		Debug(AICargo.GetCargoLabel(cargo) + ": " + producers.Count() + " producers x " + consumers.Count() + " consumers");

		foreach (producer, _ in producers) {
			foreach (consumer, _ in consumers) {
				local distance = AIMap.DistanceManhattan(AIIndustry.GetLocation(producer), AIIndustry.GetLocation(consumer));
				if (distance < MAX_CARGO_DISTANCE) {
					local route = CargoRoute(producer, consumer, cargo)
					if (route.payback > 0) {
						routes.append(route)
					}
				}
			}
		}
	}

	return routes;
}
