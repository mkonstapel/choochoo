class BuildBranchLine extends Builder {

    static MIN_BRANCH_TOWN_POPULATION = 100;
    static MAX_BRANCH_DEPTH = 4;
    
    crossing = null;
    direction = null;
    network = null;
    failedTowns = null;
    cancelled = null;
    town = null;
    candidateTowns = null;
    stationTile = null;
    
    constructor(parentTask, crossing, direction, network, failedTowns = null) {
        Builder.constructor(parentTask, crossing);
        this.crossing = crossing;
        this.direction = direction;
        this.network = network;
        this.failedTowns = failedTowns == null ? [] : failedTowns;
        this.cancelled = false;
        this.town = null;
        this.candidateTowns = [];
        this.stationTile = null;
    }
    
    function _tostring() {
        return "BuildBranchLine " + Crossing(crossing) + " " + DirectionName(direction);
    }
    
    function Cancel() {
        this.cancelled = true;
    }
    
    function Run() {
        // we can be cancelled if BuildCrossing failed
        if (cancelled) return;
        
        // see if we've not already built this direction
        // if we have subtasks but we do find rails, assume we're still building
        local entrance = Crossing(crossing).GetEntrance(direction);
        if (!subtasks && AIRail.IsRailTile(entrance[0])) {
            return;
        }
        
        if (!subtasks) {
            SetConstructionSign(crossing, this);

            local stationList = AIList();
            foreach (station in network.stations) {
                stationList.AddItem(station, 0);
            }
            stationList.Valuate(AIStation.GetDistanceManhattanToTile, crossing);
            stationList.KeepBottom(1);

            if (stationList.IsEmpty()) {
                throw TaskFailedException("can't branch off a network with no stations");
            }

            local closestMainlineStationTile = AIStation.GetLocation(stationList.Begin());
            
            local towns = FindTowns(crossing, direction, MIN_BRANCH_TOWN_POPULATION, 10, 50, 20, false);
            towns.Valuate(AITown.GetDistanceManhattanToTile, crossing);
            towns.Sort(AIList.SORT_BY_VALUE, true);
    
            local stationRotation = StationRotationForDirection(direction);
            
            // TODO: try more than station site per town?
            // NOTE: give up on a town if pathfinding fails or you might try to pathfound around the sea over and over and over...
            
            town = null;
            stationTile = null;
            for (local candidate = towns.Begin(); towns.HasNext(); candidate = towns.Next()) {
                if (ArrayContains(failedTowns, candidate)) {
                    continue;
                }

                if (!town) {
                    SetSecondarySign("Considering " + AITown.GetName(candidate));
                    Debug("Considering " + AITown.GetName(candidate));
                    stationTile = FindBranchStationSite(candidate, stationRotation, crossing);
                    if (stationTile) {
                        town = candidate;
                    }
                } else {
                    // remember if we have other options in case this town doesn't work out
                    candidateTowns.append(candidate);
                }
            }
            
            if (!stationTile) {
                throw TaskFailedException("no towns " + DirectionName(direction) + " of " + Crossing(crossing) + " where we can build a branch station");
            }
            
            // so we don't reforest tiles we're about to build on again
            local stationCoordinates = RelativeCoordinates(stationTile, stationRotation);
            local stationTiles = AITileList();
            stationTiles.AddRectangle(stationCoordinates.GetTile([0, 0]), stationCoordinates.GetTile([BRANCH_STATION_WIDTH, BRANCH_STATION_LENGTH]));

            // TODO: proper cost estimate
            // building stations is fairly cheap, but it's no use to start
            // construction if we don't have the money for pathfinding, tracks and trains 
            local costEstimate = 40000;
            
            ClearSecondarySign();
            subtasks = [
                WaitForMoney(this, costEstimate),
                AppeaseLocalAuthority(this, town),
                BuildTownBusStation(this, town),
                LevelTerrain(this, stationTile, stationRotation, [0, 0], [BRANCH_STATION_WIDTH-1, BRANCH_STATION_LENGTH-1], true),
                AppeaseLocalAuthority(this, town, stationTiles),
                BuildBranchStation(this, stationTile, direction, network, town),
                AppeaseLocalAuthority(this, town),
                BuildBusStations(this, stationTile, town),
                ConnectBranchStation(this, crossing, direction, stationTile, network),
                BuildBranchTrain(this, closestMainlineStationTile, stationTile, network, PAX)
            ];
        }
        
        RunSubtasks();

        // convert the exit to a branch connection
        // use the NE direction as a template and derive the others by rotation and offset
        local rotation;
        local offset;
        
        switch (direction) {
            case Direction.NE:
                rotation = Rotation.ROT_0;
                offset = [0,0];
                break;
            
            case Direction.SE:
                rotation = Rotation.ROT_270;
                offset = [0,3];
                break;
                
            case Direction.SW:
                rotation = Rotation.ROT_180;
                offset = [3,3];
                break;
                
            case Direction.NW:
                rotation = Rotation.ROT_90;
                offset = [3,0];
                break;
        }
        
        // move coordinate system
        if (location == crossing) {
            SetLocalCoordinateSystem(GetTile(offset), rotation);
        }
        
        if (network.rightSide) {
            RemoveRail([-1,2], [0,2], [1,2]);
            RemoveRail([1,3], [1,2], [0,2]);
            RemoveRail([2,2], [1,2], [0,2]);
            
            BuildRail([2,0], [2,1], [1,1]);
            BuildRail([1,2], [1,1], [0,1]);

            RemoveSignal([0,1], [-1, 1]);
            BuildSignal([0,1], [-1, 1], AIRail.SIGNALTYPE_PBS);
        } else {
            RemoveRail([-1,1], [0,1], [1,1]);
            RemoveRail([1,0], [1,1], [0,1]);
            RemoveRail([2,1], [1,1], [0,1]);
            
            BuildRail([2,3], [2,2], [1,2]);
            BuildRail([1,1], [1,2], [0,2]);

            RemoveSignal([0,2], [-1, 2]);
            BuildSignal([0,2], [-1, 2], AIRail.SIGNALTYPE_PBS);
        }

        // extend the branch, update train to new end of line station
        tasks.insert(1, ExtendBranchLine(null, stationTile, direction, network, MAX_BRANCH_DEPTH - 1));

        // Do branch stations get a bus service?
        
        // local towns = AITownList();
        // towns.Valuate(AITown.GetDistanceManhattanToTile, stationTile);
        // towns.KeepBelowValue(MAX_BUS_ROUTE_DISTANCE);
        
        // // sort descending, then append back-to-front so the closest actually goes first
        // towns.Sort(AIList.SORT_BY_VALUE, false);
        // for (local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
        //  tasks.insert(1, BuildBusService(null, stationTile, town));
        // }
    }
    
    function Failed() {
        Task.Failed();

        if (town && candidateTowns.len() > 0) {
            // We found a town, but failed to build or connect a station, so
            // try again in the future to see if we can expand elsewhere.
            // Since we failed, we may have troublesome geography, so expand
            // other crossings first.
            Debug(AITown.GetName(town) + " didn't work out");
            failedTowns.append(town);
            tasks.append(BuildBranchLine(null, crossing, direction, network, failedTowns));
            
            // leave the exit in place
            return;
        } else {
            // continue to clean up the exit
            Debug("no towns left to try");
        }
        
        // either we didn't find a town, or one of our subtasks failed
        local entrance = Crossing(crossing).GetEntrance(direction);
        local exit = Crossing(crossing).GetExit(direction);
        
        // use the NE direction as a template and derive the others
        // by rotation and offset
        local rotation;
        local offset;
        
        switch (direction) {
            case Direction.NE:
                rotation = Rotation.ROT_0;
                offset = [0,0];
                break;
            
            case Direction.SE:
                rotation = Rotation.ROT_270;
                offset = [0,3];
                break;
                
            case Direction.SW:
                rotation = Rotation.ROT_180;
                offset = [3,3];
                break;
                
            case Direction.NW:
                rotation = Rotation.ROT_90;
                offset = [3,0];
                break;
        }
        
        // move coordinate system
        SetLocalCoordinateSystem(GetTile(offset), rotation);
        
        // the exit might have a waypoint
        if (network.rightSide) {
            Demolish([0,2]);
        } else {
            Demolish([0,1]);
        }
        
        RemoveRail([-1,1], [0,1], [1,1]);
        RemoveRail([-1,2], [0,2], [1,2]);
        
        RemoveRail([0,1], [1,1], [1,0]);
        RemoveRail([0,1], [1,1], [2,1]);
        
        RemoveRail([0,2], [1,2], [2,2]);
        RemoveRail([0,2], [1,2], [1,3]);
        
        RemoveRail([2,2], [2,1], [1,1]);
        RemoveRail([2,1], [2,2], [1,2]);

        RemoveRail([2,0], [2,1], [1,1]);
        RemoveRail([1,2], [1,1], [0,1]);

        RemoveRail([2,3], [2,2], [1,2]);
        RemoveRail([1,1], [1,2], [0,2]);
        
        // we can remove more bits if another direction is already gone
        if (!HasRail([1,3]) && !HasRail([2,3])) {
            RemoveRail([1,1], [2,1], [3,1]);
            RemoveRail([2,0], [2,1], [2,2]);
            RemoveRail([2,1], [2,2], [2,3]);
        }
        
        if (!HasRail([1,0]) && !HasRail([1,0])) {
            RemoveRail([1,2], [2,2], [3,2]);
            RemoveRail([2,0], [2,1], [2,2]);
            RemoveRail([2,1], [2,2], [2,3]);
        }

        // TODO if only two directions remain, rename from "crossing"/"junction" to "waypoint"
    }
    
    function HasRail(tileCoords) {
        return AIRail.IsRailTile(GetTile(tileCoords));
    }
}

class ExtendBranchLine extends Builder {

    fromStationTile = null;
    fromStationID = null;
    direction = null;
    network = null;
    maxDepth = null;
    failedTowns = null;
    stationTile = null;
    town = null;
    candidateTowns = null;
    
    constructor(parentTask, fromStationTile, direction, network, maxDepth, failedTowns = null) {
        Builder.constructor(parentTask, fromStationTile);
        this.fromStationTile = fromStationTile;
        this.fromStationID = AIStation.GetStationID(fromStationTile);
        this.direction = direction;
        this.network = network;
        this.maxDepth = maxDepth;
        this.failedTowns = failedTowns == null ? [] : failedTowns;
        this.town = null;
        this.candidateTowns = [];
        this.stationTile = null;
    }
    
    function _tostring() {
        return "ExtendBranchLine " + AIStation.GetName(fromStationID);
    }
    
    function Run() {
        if (!subtasks) {
            SetConstructionSign(fromStationTile, this);

            local towns = FindTowns(fromStationTile, direction, BuildBranchLine.MIN_BRANCH_TOWN_POPULATION, 10, 50, 20, false);
            towns.Valuate(AITown.GetDistanceManhattanToTile, fromStationTile);
            towns.Sort(AIList.SORT_BY_VALUE, true);
    
            local stationRotation = StationRotationForDirection(direction);
            
            // TODO: try more than station site per town?
            // NOTE: give up on a town if pathfinding fails or you might try to pathfound around the sea over and over and over...
            
            town = null;
            stationTile = null;
            for (local candidate = towns.Begin(); towns.HasNext(); candidate = towns.Next()) {
                if (ArrayContains(failedTowns, candidate)) {
                    continue;
                }

                if (!town) {
                    SetSecondarySign("Considering " + AITown.GetName(candidate));
                    Debug("Considering " + AITown.GetName(candidate));
                    stationTile = FindBranchStationSite(candidate, stationRotation, fromStationTile);
                    if (stationTile) {
                        town = candidate;
                    }
                } else {
                    // remember if we have other options in case this town doesn't work out
                    candidateTowns.append(candidate);
                }
            }
            
            if (!stationTile) {
                throw TaskFailedException("no towns " + DirectionName(direction) + " of " + AIStation.GetName(AIStation.GetStationID(fromStationTile)) + " where we can build a branch station");
            }

            local fromStation = BranchStation(fromStationTile, stationRotation, BRANCH_STATION_PLATFORM_LENGTH);
            local toStation = BranchStation(stationTile, stationRotation, BRANCH_STATION_PLATFORM_LENGTH);
            
            // so we don't reforest tiles we're about to build on again
            local stationCoordinates = RelativeCoordinates(stationTile, stationRotation);
            local stationTiles = AITileList();
            stationTiles.AddRectangle(stationCoordinates.GetTile([0, 0]), stationCoordinates.GetTile([BRANCH_STATION_WIDTH, BRANCH_STATION_LENGTH]));

            ClearSecondarySign();
            subtasks = [
                // branches should be cheap
                // WaitForMoney(this, costEstimate),
                AppeaseLocalAuthority(this, town),
                BuildTownBusStation(this, town),
                LevelTerrain(this, stationTile, stationRotation, [0, 0], [BRANCH_STATION_WIDTH-1, BRANCH_STATION_LENGTH-1], true),
                AppeaseLocalAuthority(this, town, stationTiles),
                BuildBranchStation(this, stationTile, direction, network, town),
                AppeaseLocalAuthority(this, town),
                BuildBusStations(this, stationTile, town),
                BuildTrack(this, fromStation.GetRearExit(), toStation.GetEntrance(), [], SignalMode.NONE, network)
            ];
        }
        
        RunSubtasks();

        local train = AIVehicleList_Station(fromStationID).Begin();

        // modify/replace the last order to go to the new station
        local orderPosition = AIOrder.GetOrderCount(train) - 1;
        local orderFlags = AIOrder.GetOrderFlags(train, orderPosition);
        AIOrder.AppendOrder(train, stationTile, orderFlags);
        AIOrder.RemoveOrder(train, orderPosition);

        if (maxDepth > 1) {
            tasks.insert(1, ExtendBranchLine(null, stationTile, direction, network, maxDepth - 1));
        }
    }

    function Failed() {
        Task.Failed();

        if (town && candidateTowns.len() > 0) {
            // We found a town, but failed to build or connect a station, so
            // try again in the future to see if we can expand elsewhere.
            // Since we failed, we may have troublesome geography, so expand
            // other crossings first.
            Debug(AITown.GetName(town) + " didn't work out");
            failedTowns.append(town);
            tasks.append(ExtendBranchLine(null, fromStationTile, direction, network, maxDepth, failedTowns));
            
            // leave the exit in place
            return;
        } else {
            // continue to clean up the exit
            Debug("no towns left to try");
        }
    }
}
